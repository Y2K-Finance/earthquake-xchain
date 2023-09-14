// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IErrors} from "../../interfaces/IErrors.sol";
import {IEarthquake} from "../../interfaces/IEarthquake.sol";

abstract contract VaultController is IErrors {
    using SafeTransferLib for ERC20;
    address immutable sgEth;

    event RefundStaged(address sender, address token, uint256 amount);
    event RefundClaimed(address sender, address token, uint256 amount);

    mapping(address => mapping(address => uint256)) public eligibleRefund;

    /** @notice constructor
        @param _sgEth The address of StargateEth on Arbitrum
     **/
    constructor(address _sgEth) {
        if (_sgEth == address(0)) revert InvalidInput();
        sgEth = _sgEth;
    }

    /** @notice Deposit ERC20 or ETH to the vault
        @param id The epoch id for the Y2K vault
        @param amount The amount of the token to deposit
        @param inputToken The address of the token to deposit
        @param vaultAddress The address of the vault to deposit to
        @return bool Whether the deposit tx was successful
    **/
    function _depositToVault(
        uint256 id,
        uint256 amount,
        address inputToken,
        address vaultAddress
    ) internal returns (bool) {
        if (inputToken == sgEth) {
            try
                IEarthquake(vaultAddress).depositETH{value: amount}(
                    id,
                    address(this)
                )
            {} catch {
                return false;
            }
        } else {
            ERC20(inputToken).safeApprove(address(vaultAddress), amount);
            try
                IEarthquake(vaultAddress).deposit(id, amount, address(this))
            {} catch {
                ERC20(inputToken).safeApprove(address(vaultAddress), 0);
                return false;
            }
        }
        return true;
    }

    /** @notice Withdraw from the vault
        @param id The epoch id for the Y2K vault
        @param assets The amount of the token to withdraw
        @param receiver The address to receive the withdrawn tokens
        @param vaultAddress The address of the vault to withdraw from
    **/
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
    /** @notice Stage a refund for the original sender
        @param sender The address of the original sender
        @param token The address of the token to refund
        @param amount The amount of the token to refund
    **/
    function _stageRefund(
        address sender,
        address token,
        uint256 amount
    ) internal {
        eligibleRefund[sender][token] += amount;
        emit RefundStaged(sender, token, amount);
    }

    /** @notice Claim a refund for the original sender and token
        @param sender The address of the original sender
        @param token The address of the token to refund
    **/
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
