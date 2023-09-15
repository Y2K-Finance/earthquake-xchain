// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {WETH} from "lib/solmate/src/tokens/WETH.sol";
import {SwapController} from "./controllers/swapController.sol";
import {BytesLib} from "../libraries/BytesLib.sol";
import {IErrors} from "../interfaces/IErrors.sol";
import {IStargateRouter} from "../interfaces/bridges/IStargateRouter.sol";
import {ILayerZeroRouter} from "../interfaces/bridges/ILayerZeroRouter.sol";
import {IPermit2} from "../interfaces/IPermit2.sol";
import {ISignatureTransfer} from "../interfaces/ISignatureTransfer.sol";

/// @title Cross-chain bridge sender for Y2K Vaults
/// @notice Tokens with messages or messages can be bridged to the Y2K Bridge Router on Arbitrum
contract ZapFrom is SwapController, ISignatureTransfer {
    using SafeTransferLib for ERC20;
    uint16 public constant ARBITRUM_CHAIN_ID = 110; // NOTE: Id used by Stargate/LayerZero for Arbitrum
    IPermit2 public immutable permit2;
    address public immutable stargateRouter;
    address public immutable layerZeroRouter;
    address public immutable y2kArbRouter;
    bytes public layerZeroRemoteAndLocal;

    struct Config {
        address _stargateRouter;
        address _layerZeroRouterLocal;
        address _y2kArbRouter;
        address _uniswapV2Factory;
        address _sushiSwapFactory;
        address _uniswapV3Factory;
        address _balancerVault;
        address _wethAddress;
        address _permit2;
        bytes _primaryInitHash;
        bytes _secondaryInitHash;
    }

    /// @notice struct used to pass in the inputs for permit function
    struct PermitInput {
        address receivedToken;
        uint16 srcPoolId;
        uint16 dstPoolId;
        bytes1 dexId;
        PermitTransferFrom permit;
        SignatureTransferDetails transferDetails;
        bytes sig;
        address receiver;
        uint256 epochId;
        address vaultAddress;
        bytes swapPayload;
    }

    /** @notice constructor
        @dev The constructor calls SwapController to initialize UniswapV2, UniswapV3, Curve, and Balancer swappers
        @param _config The config struct with all the addresses needed to initialize
     **/
    constructor(
        Config memory _config
    )
        SwapController(
            _config._uniswapV2Factory,
            _config._sushiSwapFactory,
            _config._uniswapV3Factory,
            _config._balancerVault,
            _config._wethAddress,
            _config._primaryInitHash,
            _config._secondaryInitHash
        )
    {
        if (_config._stargateRouter == address(0)) revert InvalidInput();
        if (_config._layerZeroRouterLocal == address(0)) revert InvalidInput();
        if (_config._y2kArbRouter == address(0)) revert InvalidInput();
        if (_config._permit2 == address(0)) revert InvalidInput();
        stargateRouter = _config._stargateRouter;
        layerZeroRouter = _config._layerZeroRouterLocal;
        layerZeroRemoteAndLocal = abi.encodePacked(
            _config._y2kArbRouter,
            address(this)
        );
        y2kArbRouter = _config._y2kArbRouter;
        permit2 = IPermit2(_config._permit2);
    }

    //////////////////////////////////////////////
    //                 PUBLIC                   //
    //////////////////////////////////////////////
    /** @notice User invokes this function to bridge and deposit to Y2K vaults using Stargate
        @param amountIn The qty of local _token contract tokens
        @param fromToken The fromChain token address
        @param srcPoolId The poolId for the fromChain for Stargate
        @param dstPoolId The poolId for the toChain for Stargate
        @param receiver The deposit shares receiver on the dstChain
        @param epochId The epochId for the Y2K vault on the dstChain
        @param vaultAddress The vaultAddress for the Y2K vault on the dstChain
    **/
    function bridge(
        uint amountIn,
        address fromToken,
        uint16 srcPoolId,
        uint16 dstPoolId,
        address receiver,
        uint256 epochId,
        address vaultAddress
    ) external payable {
        _checkConditions(amountIn, receiver, epochId, vaultAddress);
        if (fromToken != address(0)) {
            ERC20(fromToken).safeTransferFrom(
                msg.sender,
                address(this),
                amountIn
            );
        }
        _bridge(
            amountIn,
            fromToken,
            srcPoolId,
            dstPoolId,
            abi.encode(receiver, epochId, vaultAddress)
        );
    }

    /** @notice User invokes this function to swap with Permit, bridge, and deposit to Y2K vaults using Stargate
        @dev The swap routing logic for each dex is executed on SwapController using the dexId and decoded payload
        @dev Curve uses ETH address for receiving ETH and bypasses override on line 193
        @param inp The PermitInput struct with all the inputs needed to execute the swap and bridge
    **/
    function permitSwapAndBridge(PermitInput calldata inp) external payable {
        _checkConditions(
            inp.transferDetails.requestedAmount,
            inp.receiver,
            inp.epochId,
            inp.vaultAddress
        );
        if (inp.receivedToken == address(0)) revert InvalidInput();

        permit2.permitTransferFrom(
            inp.permit,
            inp.transferDetails,
            msg.sender,
            inp.sig
        );
        uint256 receivedAmount;
        if (inp.dexId != 0x05) {
            receivedAmount = _swap(
                inp.dexId,
                inp.transferDetails.requestedAmount,
                inp.swapPayload
            );
        } else {
            ERC20(inp.permit.permitted.token).safeApprove(
                balancerVault,
                inp.transferDetails.requestedAmount
            );
            receivedAmount = _swapBalancer(inp.swapPayload);
        }

        address receivedToken = inp.receivedToken;
        if (receivedToken == wethAddress) {
            WETH(wethAddress).withdraw(receivedAmount);
            receivedToken = ETH;
        }
        _bridge(
            receivedAmount,
            receivedToken,
            inp.srcPoolId,
            inp.dstPoolId,
            abi.encode(inp.receiver, inp.epochId, inp.vaultAddress)
        );
    }

    /** @notice User invokes this function to swap, bridge and deposit to Y2K vaults using Stargate
        @dev The swap routing logic for each dex is executed on SwapController using the dexId and decoded payload
        @dev Curve uses ETH address for receiving ETH and bypasses override on line 193
        @param amountIn The qty of local _token contract tokens
        @param fromToken The fromChain token address
        @param srcPoolId The poolId for the fromChain for Stargate
        @param dstPoolId The poolId for the toChain for Stargate
        @param dexId The id for the dex to be used (1 = UniswapV2 || 2 = UniswapV3 || 3 = Sushi || 4 = Curve || 5 = Balancer)
        @param receiver The deposit shares receiver on the dstChain
        @param epochId The epochId for the Y2K vault on the dstChain
        @param vaultAddress The vaultAddress for the Y2K vault on the dstChain
        @param swapPayload The abi encoded payload for the dex being used
    **/
    function swapAndBridge(
        uint amountIn,
        address fromToken,
        address receivedToken,
        uint16 srcPoolId,
        uint16 dstPoolId,
        bytes1 dexId,
        address receiver,
        uint256 epochId,
        address vaultAddress,
        bytes calldata swapPayload
    ) external payable {
        _checkConditions(amountIn, receiver, epochId, vaultAddress);
        if (receivedToken == address(0)) revert InvalidInput();

        ERC20(fromToken).safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 receivedAmount;
        if (dexId != 0x05) {
            receivedAmount = _swap(dexId, amountIn, swapPayload);
        } else {
            ERC20(fromToken).safeApprove(balancerVault, amountIn);
            receivedAmount = _swapBalancer(swapPayload);
        }

        if (receivedToken == wethAddress) {
            WETH(wethAddress).withdraw(receivedAmount);
            receivedToken = ETH;
        }

        _bridge(
            receivedAmount,
            receivedToken,
            srcPoolId,
            dstPoolId,
            abi.encode(receiver, epochId, vaultAddress)
        );
    }

    /** @notice User invokes this function to send a message to withdraw, withdrawAndBridge, or withdrawSwapAndBridge
        @dev Bridging transactions will only bridge back to the fromChain
        @param payload The abi encoded payload to conduct actions on the dest contract
    **/
    function withdraw(bytes memory payload) external payable {
        if (msg.value == 0) revert InvalidInput();
        payload = replaceReceiver(payload);
        ILayerZeroRouter(layerZeroRouter).send{value: msg.value}(
            uint16(ARBITRUM_CHAIN_ID), // destination LayerZero chainId
            layerZeroRemoteAndLocal, // send to this address on the destination
            payload, // bytes payload
            payable(msg.sender), // refund address
            address(0x0), // future parameter
            bytes("") // adapterParams (see "Advanced Features")
        );
    }

    //////////////////////////////////////////////
    //                 INTERNAL                 //
    //////////////////////////////////////////////
    /** @notice Slices the msg.sender into the 32 byte slot reserved for receiver
        @dev Data is decoded on the destChain and receiver is used for withdrawal - limits withdrawals to owners
        @param payload The data to be decoded and used for withdrawal action on the destChain
    **/
    function replaceReceiver(
        bytes memory payload
    ) internal view returns (bytes memory) {
        payload = BytesLib.concat(
            BytesLib.concat(
                BytesLib.sliceBytes(payload, 0, 0x40),
                abi.encode(msg.sender)
            ),
            BytesLib.sliceBytes(payload, 0x60, payload.length - 0x60)
        );

        return payload;
    }

    /** @notice Checks msg.value and amountIn for valid input
        @dev Message value must be > 0 to pay for Stargate/LayerZero relayer fees
        @param amountIn The amount of fromToken in
    **/
    function _checkConditions(
        uint256 amountIn,
        address receiver,
        uint256 epochId,
        address vaultAddress
    ) private {
        if (msg.value == 0) revert InvalidInput();
        if (amountIn == 0) revert InvalidInput();
        if (receiver == address(0)) revert InvalidReceiver();
        if (epochId == 0) revert InvalidEpochId();
        if (vaultAddress == address(0)) revert InvalidVault();
    }

    /** @notice Routes the bridge with payload action to the Stargate router
        @param amountIn The amount of fromToken being bridged
        @param fromToken The fromToken being bridged
        @param srcPoolId The poolId for the fromChain for Stargate
        @param dstPoolId The poolId for the toChain for Stargate
        @param payload The abi encoded payload for instructions on the dest contract
    **/
    function _bridge(
        uint amountIn,
        address fromToken,
        uint16 srcPoolId,
        uint16 dstPoolId,
        bytes memory payload
    ) private {
        if (fromToken == ETH) {
            /*  NOTE: If sending after swap to ETH then msg.value will be < amountIn as it only contains the fee
                If sending without swap msg.value will be > amountIn as it contains both fee + amountIn
            **/
            uint256 msgValue = msg.value > amountIn
                ? msg.value
                : amountIn + msg.value;
            IStargateRouter(stargateRouter).swapETHAndCall{value: msgValue}(
                uint16(ARBITRUM_CHAIN_ID), // destination Stargate chainId
                payable(msg.sender), // refund additional messageFee to this address
                abi.encodePacked(y2kArbRouter), // the receiver of the destination ETH
                IStargateRouter.SwapAmount(amountIn, (amountIn * 950) / 1000),
                IStargateRouter.lzTxObj(200000, 0, "0x"), // default lzTxObj
                payload // the payload to send to the destination
            );
        } else {
            ERC20(fromToken).safeApprove(stargateRouter, amountIn);
            IStargateRouter(stargateRouter).swap{value: msg.value}(
                uint16(ARBITRUM_CHAIN_ID), // the destination chain id
                srcPoolId, // the source Stargate poolId
                dstPoolId, // the destination Stargate poolId
                payable(msg.sender), // refund adddress. if msg.sender pays too much gas, return extra eth
                amountIn, // total tokens to send to destination chain
                (amountIn * 950) / 1000, // min amount allowed out
                IStargateRouter.lzTxObj(200000, 0, "0x"), // default lzTxObj
                abi.encodePacked(y2kArbRouter), // destination address, the sgReceive() implementer
                payload
            );
        }
    }

    receive() external payable {}

    fallback() external payable {}
}
