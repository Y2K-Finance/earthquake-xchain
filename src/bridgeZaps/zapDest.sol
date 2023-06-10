// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {VaultController} from "./controllers/vaultController.sol";
import {BridgeController} from "./controllers/bridgeController.sol";
import {IStargateReceiver} from "../interfaces/bridges/IStargateReceiver.sol";
import {ILayerZeroReceiver} from "../interfaces/bridges/ILayerZeroReceiver.sol";
import {ERC1155Holder} from "lib/openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "forge-std/console.sol";

contract ZapDest is
    Ownable,
    ERC1155Holder,
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
    event TrustedRemoteAdded(
        uint16 chainId,
        bytes trustedAddress,
        address sender
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
    function setTrustedRemoteLookup(
        uint16 srcChainId,
        bytes calldata trustedAddress
    ) external onlyOwner {
        if (keccak256(trustedAddress) == keccak256(bytes("")))
            revert InvalidInput();
        trustedRemoteLookup[srcChainId] = trustedAddress;
        emit TrustedRemoteAdded(srcChainId, trustedAddress, msg.sender);
    }

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
        if (msg.sender != STARGATE_RELAYER) revert InvalidCaller();
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
        if (msg.sender != LAYER_ZERO_ENDPOINT) revert InvalidCaller();
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

        // decode data for function
        (
            bytes1 funcSelector,
            bytes1 bridgeId,
            address receiver,
            uint256 id
        ) = abi.decode(_payload, (bytes1, bytes1, address, uint256));

        _withdraw(funcSelector, bridgeId, receiver, id, _srcChainId);
    }

    function withdraw(
        bytes1 funcSelector,
        bytes1 bridgeId,
        uint256 id,
        uint16 _srcChainId
    ) external {
        _withdraw(funcSelector, bridgeId, msg.sender, id, _srcChainId);
    }

    function _withdraw(
        bytes1 funcSelector,
        bytes1 bridgeId,
        address receiver,
        uint256 id,
        uint16 _srcChainId
    ) private {
        // check assets to withdraw
        uint256 assets = addressToIdToAmount[receiver][id];
        if (assets == 0) revert NullBalance();
        delete addressToIdToAmount[receiver][id];

        // assets convert 1:1 when depositing meaning this should withdraw assets + rewards
        if (funcSelector == 0x01)
            _withdrawFromVault(id, assets, receiver);
            // withdraws assets to vault and bridges to source
        else if (funcSelector == 0x02) {
            uint256 amountReceived = _withdrawFromVault(
                id,
                assets,
                address(this)
            );
            _bridgeToSource(
                bridgeId,
                receiver,
                EARTHQUAKE_VAULT.asset(),
                amountReceived,
                _srcChainId
            );
        } else revert InvalidInput();

        emit ReceivedWithdrawal(funcSelector, receiver, assets);
    }
}
