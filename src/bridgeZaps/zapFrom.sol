// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {SwapController} from "./controllers/swapController.sol";
import {IErrors} from "../interfaces/IErrors.sol";
import {IStargateRouter} from "../interfaces/bridges/IStargateRouter.sol";
import {ILayerZeroRouter} from "../interfaces/bridges/ILayerZeroRouter.sol";

contract ZapFrom is IErrors, SwapController {
    using SafeTransferLib for ERC20;
    // TODO: Best way to use a uint16 for the input in router?
    uint256 public constant ARBITRUM_CHAIN_ID = 110; // NOTE: ID used by Stargate for Arbitrum
    // TODO: Value must be abi.encodePacked(bytes);
    // TODO: Review the destStargateComposed construction which we substitute ARB_RECEIVER for
    bytes public constant ARB_RECEIVER = "0x00";
    address public immutable stargateRouter;
    address public immutable stargateRouterEth;
    address public immutable layerZeroRouter;
    address public immutable y2kArbRouter;
    // TODO: Make this constant?
    bytes public layerZeroRemoteAndLocal;

    constructor(
        address _stargateRouter,
        address _stargateRouterEth,
        address _layerZeroRouterRemote,
        address _layerZeroRouterLocal,
        address _y2kArbRouter,
        address _uniswapV2Factory,
        address _sushiSwapFactory,
        address _uniswapV3Factory,
        address _balancerVault
    )
        SwapController(
            _uniswapV2Factory,
            _sushiSwapFactory,
            _uniswapV3Factory,
            _balancerVault
        )
    {
        if (_stargateRouter == address(0)) revert InvalidInput();
        if (_stargateRouterEth == address(0)) revert InvalidInput();
        if (_layerZeroRouterRemote == address(0)) revert InvalidInput();
        if (_layerZeroRouterLocal == address(0)) revert InvalidInput();
        if (_y2kArbRouter == address(0)) revert InvalidInput();
        stargateRouter = _stargateRouter;
        stargateRouterEth = _stargateRouterEth;
        layerZeroRouter = _layerZeroRouterLocal;
        layerZeroRemoteAndLocal = abi.encodePacked(
            _layerZeroRouterRemote,
            _layerZeroRouterLocal
        );
        y2kArbRouter = _y2kArbRouter;
    }

    //////////////////////////////////////////////
    //                 PUBLIC                   //
    //////////////////////////////////////////////
    /// @param amountIn The qty of local _token contract tokens
    /// @param fromToken The fromChain token address
    /// @param srcPoolId The poolId for the fromChain
    /// @param dstPoolId The poolId for the toChain
    /// @param payload The encoded payload to deposit into vault abi.encode(receiver, vaultId)
    function bridge(
        uint amountIn,
        address fromToken,
        uint16 srcPoolId,
        uint16 dstPoolId,
        bytes calldata payload
    ) external payable {
        if (msg.value == 0) revert InvalidInput();
        if (amountIn == 0) revert InvalidInput();

        ERC20(fromToken).safeTransferFrom(msg.sender, address(this), amountIn);
        _bridge(amountIn, fromToken, srcPoolId, dstPoolId, payload);
    }

    function permitSwapAndBridge(
        uint amountIn,
        address fromToken,
        address receivedToken,
        uint16 srcPoolId,
        uint16 dstPoolId,
        bytes calldata swapPayload,
        bytes calldata bridgePayload
    ) external payable {
        if (msg.value == 0) revert InvalidInput();
        if (amountIn == 0) revert InvalidInput();

        // TODO: implement permit2 for the fromToken transfer
        ERC20(fromToken).safeTransferFrom(msg.sender, address(this), amountIn);
        uint256 receivedAmount = _swap(
            swapPayload[0],
            amountIn,
            swapPayload[32:]
        );
        _bridge(
            receivedAmount,
            receivedToken,
            srcPoolId,
            dstPoolId,
            bridgePayload
        );
    }

    function swapAndBridge(
        uint amountIn,
        address fromToken,
        address receivedToken,
        uint16 srcPoolId,
        uint16 dstPoolId,
        bytes calldata swapPayload,
        bytes calldata bridgePayload
    ) external payable {
        if (msg.value == 0) revert InvalidInput();
        if (amountIn == 0) revert InvalidInput();

        ERC20(fromToken).safeTransferFrom(msg.sender, address(this), amountIn);
        uint256 receivedAmount = _swap(
            swapPayload[0],
            amountIn,
            swapPayload[32:]
        );
        _bridge(
            receivedAmount,
            receivedToken,
            srcPoolId,
            dstPoolId,
            bridgePayload
        );
    }

    // TODO: Check the construction of the remote and local variables
    function withdraw(bytes memory payload) external payable {
        if (msg.value == 0) revert InvalidInput();
        ILayerZeroRouter(layerZeroRouter).send{value: msg.value}(
            uint16(ARBITRUM_CHAIN_ID), // TODO: destination LayerZero chainId
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
    function _bridge(
        uint amountIn,
        address fromToken,
        uint16 srcPoolId,
        uint16 dstPoolId,
        bytes calldata payload
    ) private {
        if (fromToken == address(0)) {
            IStargateRouter(stargateRouterEth).swapETHAndCall{value: msg.value}(
                uint16(ARBITRUM_CHAIN_ID), // destination Stargate chainId
                payable(msg.sender), // refund additional messageFee to this address
                ARB_RECEIVER, // the receiver of the destination ETH
                IStargateRouter.SwapAmount(amountIn, 0), // TODO: the amount and the minimum swap amount
                IStargateRouter.lzTxObj(200000, 0, "0x"), // default lzTxObj
                payload // the payload to send to the destination
            );
        } else {
            ERC20(fromToken).safeApprove(stargateRouter, amountIn);
            // Sends tokens to the destChain
            IStargateRouter(stargateRouter).swap{value: msg.value}(
                uint16(ARBITRUM_CHAIN_ID), // the destination chain id
                srcPoolId, // the source Stargate poolId
                dstPoolId, // the destination Stargate poolId
                payable(msg.sender), // refund adddress. if msg.sender pays too much gas, return extra eth
                amountIn, // total tokens to send to destination chain
                0, // min amount allowed out
                IStargateRouter.lzTxObj(200000, 0, "0x"), // default lzTxObj
                ARB_RECEIVER, // destination address, the sgReceive() implementer
                payload
            );
        }
    }
}
