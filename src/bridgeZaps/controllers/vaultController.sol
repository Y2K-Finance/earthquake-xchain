// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IErrors} from "../../interfaces/IErrors.sol";
import {IEarthquake} from "../../interfaces/IEarthquake.sol";

import "forge-std/console.sol";

abstract contract VaultController is IErrors {
    using SafeTransferLib for ERC20;
    address immutable sgEth;

    event RefundStaged(address sender, address token, uint256 amount);
    event RefundClaimed(address sender, address token, uint256 amount);

    mapping(address => mapping(address => uint256)) public eligibleRefund;

    constructor(address _sgEth) {
        if (_sgEth == address(0)) revert InvalidInput();
        sgEth = _sgEth;
    }

    function _depositToVault(
        uint256 id,
        uint256 amount,
        address receiver,
        address inputToken,
        address vaultAddress,
        address refundReceiver
    ) internal returns (bool) {
        if (inputToken == sgEth) {
            try
                IEarthquake(vaultAddress).depositETH{
                    value: address(this).balance
                }(id, receiver)
            {} catch {
                return false;
            }
        } else {
            ERC20(inputToken).safeApprove(address(vaultAddress), amount);
            try
                IEarthquake(vaultAddress).deposit(id, amount, receiver)
            {} catch {
                return false;
            }
        }
        return true;
    }

    function _withdrawFromVault(
        uint256 id,
        uint256 assets,
        address receiver,
        address vaultAddress
    ) internal returns (uint256) {
        return
            IEarthquake(vaultAddress).withdraw(
                id,
                assets,
                receiver,
                address(this)
            );
    }

    //////////////////////////////////////////////
    //                 REFUND LOGIC             //
    //////////////////////////////////////////////
    function _stageRefund(
        address sender,
        address token,
        uint256 amount
    ) internal {
        eligibleRefund[sender][token] += amount;
        emit RefundStaged(sender, token, amount);
    }

    function _claimRefund(address sender, address token) internal {
        uint256 amount = eligibleRefund[sender][token];
        if (amount == 0) revert IneligibleRefund();
        delete eligibleRefund[sender][token];

        if (token == sgEth) {
            (bool success, bytes memory data) = payable(sender).call{
                value: amount
            }("");
            if (!success) revert FailedCall(data);
        } else ERC20(token).safeTransfer(sender, amount);

        emit RefundClaimed(sender, token, amount);
    }
}
