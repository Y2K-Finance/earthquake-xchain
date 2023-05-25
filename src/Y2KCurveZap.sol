// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IEarthquake} from "./interfaces/IEarthquake.sol";
import {IErrors} from "./interfaces/IErrors.sol";
import {ICurvePair} from "./interfaces/ICurvePair.sol";

import "lib/forge-std/src/console.sol";

contract Y2KCurveZap is IErrors {
    using SafeTransferLib for ERC20;
    address public immutable EARTHQUAKE_VAULT;

    constructor(address _earthquakeVault) {
        if (_earthquakeVault == address(0)) revert InvalidInput();
        EARTHQUAKE_VAULT = _earthquakeVault;
    }

    function zapInSingle(
        address fromToken,
        address toToken,
        int128 i,
        int128 j,
        address pool,
        uint256 fromAmount,
        uint256 toAmountIn,
        uint256 id
    ) external {
        ERC20(fromToken).safeTransferFrom(
            msg.sender,
            address(this),
            fromAmount
        );
        uint256 cachedBalance = ERC20(toToken).balanceOf(address(this));

        ERC20(fromToken).safeApprove(pool, fromAmount);
        ICurvePair(pool).exchange(i, j, fromAmount, toAmountIn);
        uint256 amountOut = ERC20(toToken).balanceOf(address(this)) -
            cachedBalance;
        if (amountOut == 0) revert InvalidOutput();

        ERC20(toToken).safeApprove(EARTHQUAKE_VAULT, amountOut);
        IEarthquake(EARTHQUAKE_VAULT).deposit(id, amountOut, msg.sender); // NOTE: Could take receiver input
    }

    function zapInSingleEth(
        address fromToken,
        address toToken,
        uint256 i,
        uint256 j,
        address pool,
        uint256 fromAmount,
        uint256 toAmountIn,
        uint256 id,
        bool toEth
    ) external payable {
        uint256 cachedBalance;
        uint256 amountOut;

        if (msg.value == 0) {
            cachedBalance = toEth
                ? address(this).balance
                : ERC20(toToken).balanceOf(address(this));
            ERC20(fromToken).safeTransferFrom(
                msg.sender,
                address(this),
                fromAmount
            );
            ERC20(fromToken).safeApprove(pool, fromAmount);
            ICurvePair(pool).exchange(i, j, fromAmount, toAmountIn, toEth);
            amountOut = toEth
                ? address(this).balance - cachedBalance
                : ERC20(toToken).balanceOf(address(this)) - cachedBalance;
            if (amountOut == 0) revert InvalidOutput();
            if (toEth) {
                IEarthquake(EARTHQUAKE_VAULT).depositETH{value: amountOut}(
                    id,
                    msg.sender
                );
            } else {
                ERC20(toToken).safeApprove(EARTHQUAKE_VAULT, amountOut);
                IEarthquake(EARTHQUAKE_VAULT).deposit(
                    id,
                    amountOut,
                    msg.sender
                ); // NOTE: Could take receiver input
            }
        } else {
            cachedBalance = ERC20(toToken).balanceOf(address(this));
            ERC20(fromToken).safeApprove(pool, fromAmount);
            ICurvePair(pool).exchange{value: msg.value}(
                i,
                j,
                fromAmount,
                toAmountIn,
                false
            );
            amountOut = ERC20(toToken).balanceOf(address(this)) - cachedBalance;
            if (amountOut == 0) revert InvalidOutput();
            ERC20(toToken).safeApprove(EARTHQUAKE_VAULT, amountOut);
            IEarthquake(EARTHQUAKE_VAULT).deposit(id, amountOut, msg.sender); // NOTE: Could take receiver input
        }
    }

    function _swap(
        address[] calldata path,
        uint256 fromAmount,
        uint256 toAmountMin
    ) internal returns (uint256 amountOut) {}
}
