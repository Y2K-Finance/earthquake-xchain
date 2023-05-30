// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ZapController} from "./zapController.sol";
import {IStargateReceiver} from "../interfaces/IStargateReceiver.sol";

contract ZapDest is ZapController, IStargateReceiver {
    address public immutable STARGATE_RELAYER;

    event ReceivedOnDestination(address token, uint256 amount);

    constructor(
        address stargateRelayer,
        address _earthquakeVault
    ) ZapController(_earthquakeVault) {
        if (stargateRelayer == address(0)) revert InvalidInput();
        STARGATE_RELAYER = stargateRelayer;
    }

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
        emit ReceivedOnDestination(_token, amountLD);
        _depositToVault(id, amountLD, receiver, _token);
    }
}
