// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {VaultController} from "./controllers/vaultController.sol";
import {BridgeController} from "./controllers/bridgeController.sol";
import {BytesLib} from "../libraries/BytesLib.sol";
import {UniswapV3Swapper} from "./dexHelpers/uniswapV3.sol";
import {UniswapV2Swapper} from "./dexHelpers/uniswapV2.sol";

import {IStargateReceiver} from "../interfaces/bridges/IStargateReceiver.sol";
import {ILayerZeroReceiver} from "../interfaces/bridges/ILayerZeroReceiver.sol";
import {ERC1155Holder} from "lib/openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract ZapDest is
    Ownable,
    ERC1155Holder,
    VaultController,
    BridgeController,
    UniswapV2Swapper,
    UniswapV3Swapper,
    IStargateReceiver,
    ILayerZeroReceiver
{
    using BytesLib for bytes;
    address public immutable stargateRelayer;
    address public immutable layerZeroRelayer;

    mapping(address => uint256) public addrCounter;
    mapping(uint16 => bytes) public trustedRemoteLookup;
    mapping(bytes1 => address) public idToExchange;
    mapping(address => mapping(uint256 => uint256)) public addressToIdToAmount;

    event ReceivedDeposit(address token, address receiver, uint256 amount);
    event ReceivedWithdrawal(
        bytes1 orderType,
        address receiver,
        uint256 amount
    );
    event TrustedRemoteAdded(
        uint16 chainId,
        bytes trustedAddress,
        address sender
    );
    event TokenToHopBridgeSet(
        address[] tokens,
        address[] bridges,
        address sender
    );

    constructor(
        address _stargateRelayer,
        address _layerZeroRelayer,
        address _earthquakeVault,
        address celerBridge,
        address hyphenBridge,
        address uniswapV2Factory,
        address sushiSwapFactory,
        address uniswapV3Factory
    )
        VaultController(_earthquakeVault)
        BridgeController(celerBridge, hyphenBridge)
        UniswapV2Swapper(uniswapV2Factory, sushiSwapFactory)
        UniswapV3Swapper(uniswapV3Factory)
    {
        if (_stargateRelayer == address(0)) revert InvalidInput();
        if (_layerZeroRelayer == address(0)) revert InvalidInput();
        stargateRelayer = _stargateRelayer;
        layerZeroRelayer = _layerZeroRelayer;
    }

    //////////////////////////////////////////////
    //                 ADMIN                   //
    //////////////////////////////////////////////
    function setTrustedRemoteLookup(
        uint16 srcChainId,
        bytes calldata trustedAddress
    ) external onlyOwner {
        if (keccak256(trustedAddress) == keccak256(bytes("")))
            revert InvalidInput();
        trustedRemoteLookup[srcChainId] = trustedAddress;
        emit TrustedRemoteAdded(srcChainId, trustedAddress, msg.sender);
    }

    function setTokenToHopBridge(
        address[] calldata _tokens,
        address[] calldata _bridges
    ) external onlyOwner {
        if (_tokens.length != _bridges.length) revert InvalidInput();
        for (uint256 i = 0; i < _tokens.length; ) {
            tokenToHopBridge[_tokens[i]] = _bridges[i];
            unchecked {
                i++;
            }
        }
        emit TokenToHopBridgeSet(_tokens, _bridges, msg.sender);
    }

    //////////////////////////////////////////////
    //                 PUBLIC                   //
    //////////////////////////////////////////////s
    /// @param _chainId The remote chainId sending the tokens
    /// @param _srcAddress The remote Bridge address
    /// @param _nonce The message ordering nonce
    /// @param _token The token contract on the local chain
    /// @param amountLD The qty of local _token contract tokens
    /// @param _payload The bytes containing the toAddress
    // TODO: Confirm correct checks happening for amountLD/ _token on srcChain
    function sgReceive(
        uint16 _chainId,
        bytes memory _srcAddress,
        uint256 _nonce,
        address _token,
        uint256 amountLD,
        bytes memory _payload
    ) external override {
        if (msg.sender != stargateRelayer) revert InvalidCaller();
        (address receiver, uint256 id) = abi.decode(
            _payload,
            (address, uint256)
        );

        // TODO: Check the efficiency of this vs. +=
        addressToIdToAmount[receiver][id] =
            addressToIdToAmount[receiver][id] +
            amountLD;

        // NOTE: The relayer holds the balance of all tokens
        _depositToVault(id, amountLD, address(this), _token);

        emit ReceivedDeposit(_token, address(this), amountLD);
    }

    // @notice LayerZero endpoint will invoke this function to deliver the message on the destination
    // @param _srcChainId - the source endpoint identifier
    // @param _srcAddress - the source sending contract address from the source chain
    // @param _nonce - the ordered message nonce
    // @param _payload - the signed payload is the UA bytes has encoded to be sent
    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) external override {
        if (msg.sender != layerZeroRelayer) revert InvalidCaller();
        if (
            keccak256(_srcAddress) !=
            keccak256(trustedRemoteLookup[_srcChainId])
        ) revert InvalidCaller();

        // iterate the addrCounter - suggested by LZ
        address fromAddress;
        assembly {
            fromAddress := mload(add(_srcAddress, 20))
        }
        addrCounter[fromAddress] += 1;

        // decode data for function - additional data needed to append?
        (
            bytes1 funcSelector,
            bytes1 bridgeId,
            address receiver,
            uint256 id
        ) = abi.decode(_payload, (bytes1, bytes1, address, uint256));
        if (funcSelector == 0x00) revert InvalidFunctionId();

        _payload = _payload.length == 128
            ? bytes("")
            : _payload.sliceBytes(128, _payload.length - 128);

        _withdraw(funcSelector, bridgeId, receiver, id, _srcChainId, _payload);
    }

    function withdraw(
        bytes1 funcSelector,
        bytes1 bridgeId,
        uint256 id,
        uint16 _srcChainId,
        bytes memory _withdrawPayload
    ) external {
        _withdraw(
            funcSelector,
            bridgeId,
            msg.sender,
            id,
            _srcChainId,
            _withdrawPayload
        );
    }

    //////////////////////////////////////////////
    //                 PRIVATE                  //
    //////////////////////////////////////////////
    function _withdraw(
        bytes1 funcSelector,
        bytes1 bridgeId,
        address receiver,
        uint256 id,
        uint16 _srcChainId,
        bytes memory _payload
    ) private {
        uint256 assets = addressToIdToAmount[receiver][id];
        if (assets == 0) revert NullBalance();
        delete addressToIdToAmount[receiver][id];

        // NOTE: If !=0 0x00 && !0x01 && <4 then id is 0x02 or 0x03
        if (funcSelector == 0x01) _withdrawFromVault(id, assets, receiver);
        else if (uint8(funcSelector) < 4) {
            uint256 amountReceived = _withdrawFromVault(
                id,
                assets,
                address(this)
            );
            address asset = earthquakeVault.asset();
            // NOTE: Re-using amountReceived for bridge input
            if (funcSelector == 0x03)
                (asset, _payload, amountReceived) = _swapToBridgeToken(
                    amountReceived,
                    asset,
                    _payload
                );
            _bridgeToSource(
                bridgeId,
                receiver,
                asset,
                amountReceived,
                _srcChainId,
                _payload
            );
        } else revert InvalidFunctionId();
        emit ReceivedWithdrawal(funcSelector, receiver, assets);
    }

    function _swapToBridgeToken(
        uint256 swapAmount,
        address token,
        bytes memory _payload
    ) internal returns (address, bytes memory, uint256 amountOut) {
        (
            bytes1 swapId,
            uint256 toAmountMin,
            bytes1 dexId,
            address toToken
        ) = abi.decode(_payload, (bytes1, uint256, bytes1, address));

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = toToken;

        if (swapId == 0x01) {
            bytes memory swapPayload = abi.encode(path, toAmountMin);
            amountOut = _swapUniswapV2(dexId, swapAmount, swapPayload);
            _payload = _payload.sliceBytes(128, _payload.length - 128);
        } else if (swapId == 0x02) {
            uint24[] memory fee = new uint24[](1);
            (, , , , fee[0]) = abi.decode(
                _payload,
                (bytes1, uint256, bytes1, address, uint24)
            );
            bytes memory swapPayload = abi.encode(path, fee, toAmountMin);
            amountOut = _swapUniswapV3(swapAmount, swapPayload);
            _payload = _payload.sliceBytes(160, _payload.length - 160);
        } else revert InvalidSwapId();
        return (toToken, _payload, amountOut);
    }
}
