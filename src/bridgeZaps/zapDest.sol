// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {VaultController} from "./controllers/vaultController.sol";
import {BridgeController} from "./controllers/bridgeController.sol";
import {IStargateReceiver} from "../interfaces/bridges/IStargateReceiver.sol";
import {ILayerZeroReceiver} from "../interfaces/bridges/ILayerZeroReceiver.sol";

contract ZapDest is
    VaultController,
    BridgeController,
    IStargateReceiver,
    ILayerZeroReceiver
{
    address public immutable STARGATE_RELAYER;
    address public immutable LAYER_ZERO_ENDPOINT;

    mapping(address => uint256) public addrCounter;
    mapping(uint16 => bytes) public trustedRemoteLookup;
    mapping(address => mapping(uint256 => uint256)) public addressToIdToAmount;

    event ReceivedDeposit(address token, address receiver, uint256 amount);
    event ReceivedWithdrawal(
        bytes1 orderType,
        address receiver,
        uint256 amount
    );

    constructor(
        address stargateRelayer,
        address layerZeroEndpoint,
        address _earthquakeVault,
        address celerBridge,
        address hyphenBridge,
        address connextBridge
    )
        VaultController(_earthquakeVault)
        BridgeController(celerBridge, hyphenBridge, connextBridge)
    {
        if (stargateRelayer == address(0)) revert InvalidInput();
        if (layerZeroEndpoint == address(0)) revert InvalidInput();
        STARGATE_RELAYER = stargateRelayer;
        LAYER_ZERO_ENDPOINT = layerZeroEndpoint;
    }

    //////////////////////////////////////////////
    //                 PUBLIC                   //
    //////////////////////////////////////////////
    /// @param _chainId The remote chainId sending the tokens
    /// @param _srcAddress The remote Bridge address
    /// @param _nonce The message ordering nonce
    /// @param _token The token contract on the local chain
    /// @param amountLD The qty of local _token contract tokens
    /// @param _payload The bytes containing the toAddress
    function sgReceive(
        uint16 _chainId,
        bytes memory _srcAddress,
        uint _nonce,
        address _token,
        uint amountLD,
        bytes memory _payload
    ) external override {
        if (msg.sender != STARGATE_RELAYER) revert InvalidCaller();
        (address receiver, uint256 id) = abi.decode(
            _payload,
            (address, uint256)
        );

        // TODO: Check the efficiency of this vs. +=
        addressToIdToAmount[receiver][id] =
            addressToIdToAmount[receiver][id] +
            amountLD;

        _depositToVault(id, amountLD, receiver, _token);

        emit ReceivedDeposit(_token, receiver, amountLD);
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) external override {
        if (msg.sender != LAYER_ZERO_ENDPOINT) revert InvalidCaller();
        if (
            keccak256(_srcAddress) !=
            keccak256(trustedRemoteLookup[_srcChainId])
        ) revert InvalidCaller();

        // decode data for function
        (
            bytes1 funcSelector,
            bytes1 bridgeId,
            address receiver,
            uint256 id
        ) = abi.decode(_payload, (bytes1, bytes1, address, uint256));

        // check assets to withdraw
        uint256 assets = addressToIdToAmount[receiver][id];
        if (assets == 0) revert NullBalance();
        delete addressToIdToAmount[receiver][id];

        // iterate the addrCounter - suggested by LZ
        address fromAddress;
        assembly {
            fromAddress := mload(add(_srcAddress, 20))
        }
        addrCounter[fromAddress] += 1;

        // assets convert 1:1 when depositing meaning this should withdraw assets + rewards
        if (funcSelector == 0x01)
            _withdrawFromVault(id, assets, receiver);
            // withdraws assets to vault and bridges to source
        else if (funcSelector == 0x02) {
            uint256 shares = _withdrawFromVault(id, assets, receiver);
            _bridgeToSource(
                bridgeId,
                receiver,
                EARTHQUAKE_VAULT.asset(),
                shares,
                _srcChainId
            );
        } else revert InvalidInput();
        // TODO: should we emit two different events for withdraw and bridge?
        emit ReceivedWithdrawal(funcSelector, receiver, assets);
    }
}
