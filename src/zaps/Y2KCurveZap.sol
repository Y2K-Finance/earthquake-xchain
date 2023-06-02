// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IEarthquake} from "../interfaces/IEarthquake.sol";
import {IErrors} from "../interfaces/IErrors.sol";
import {ICurvePair} from "../interfaces/dexes/ICurvePair.sol";

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
        uint256 toAmountMin,
        uint256 id
    ) external {
        ERC20(fromToken).safeTransferFrom(
            msg.sender,
            address(this),
            fromAmount
        );
        uint256 amountOut = _swap(
            fromToken,
            toToken,
            pool,
            i,
            j,
            fromAmount,
            toAmountMin
        );
        if (amountOut == 0) revert InvalidOutput();
        _deposit(toToken, amountOut, id);
    }

    function zapInSingleEth(
        address fromToken,
        address toToken,
        uint256 i,
        uint256 j,
        address pool,
        uint256 fromAmount,
        uint256 toAmountIn,
        uint256 id
    ) external payable {
        ERC20(fromToken).safeTransferFrom(
            msg.sender,
            address(this),
            fromAmount
        );
        uint256 amountOut = _swapEth(
            fromToken,
            toToken,
            pool,
            i,
            j,
            fromAmount,
            toAmountIn
        );
        if (amountOut == 0) revert InvalidOutput();
        _deposit(toToken, amountOut, id);
    }

    // NOTE: Logic has to be abstract to avoid stack too deep errors
    function zapInMulti(
        address[] calldata path,
        address[] calldata pools,
        uint256[] calldata iValues,
        uint256[] calldata jValues,
        uint256 fromAmount,
        uint256 toAmountMin,
        uint256 id
    ) external {
        ERC20(path[0]).safeTransferFrom(msg.sender, address(this), fromAmount);
        uint256 amountOut = _multiSwap(
            path,
            pools,
            iValues,
            jValues,
            fromAmount
        );
        if (amountOut < toAmountMin) revert InvalidOutput();
        if (amountOut == 0) revert InvalidOutput();
        _deposit(path[path.length - 1], amountOut, id);
    }

    function _multiSwap(
        address[] calldata path,
        address[] calldata pools,
        uint256[] calldata iValues,
        uint256[] calldata jValues,
        uint256 fromAmount
    ) internal returns (uint256 amountOut) {
        amountOut = fromAmount;
        for (uint256 i = 0; i < pools.length - 1; ) {
            amountOut = _swap(
                path[i],
                path[i + 1],
                pools[i],
                int128(int256(iValues[i])),
                int128(int256(jValues[i])),
                amountOut,
                0
            );
            unchecked {
                i++;
            }
        }
        return
            _swapEth(
                path[path.length - 2],
                path[path.length - 1],
                pools[pools.length - 1],
                iValues[pools.length - 1],
                jValues[pools.length - 1],
                amountOut,
                0
            );
    }

    function _swap(
        address fromToken,
        address toToken,
        address pool,
        int128 i,
        int128 j,
        uint256 fromAmount,
        uint256 toAmountIn
    ) internal returns (uint256) {
        ERC20(fromToken).safeApprove(pool, fromAmount);
        uint256 cachedBalance = ERC20(toToken).balanceOf(address(this));
        // TODO: Check if this works when swapping with ETH pools + compatibility due to int128 conversions?
        ICurvePair(pool).exchange(i, j, fromAmount, toAmountIn);
        fromAmount = ERC20(toToken).balanceOf(address(this)) - cachedBalance;

        return fromAmount;
    }

    function _swapEth(
        address fromToken,
        address toToken,
        address pool,
        uint256 i,
        uint256 j,
        uint256 fromAmount,
        uint256 toAmountIn
    ) internal returns (uint256) {
        ERC20(fromToken).safeApprove(pool, fromAmount);
        uint256 cachedBalance = ERC20(toToken).balanceOf(address(this));
        // TODO: Check if this works when swapping with ETH pools + compatibility due to int128 conversions?
        ICurvePair(pool).exchange(i, j, fromAmount, toAmountIn, false);
        fromAmount = ERC20(toToken).balanceOf(address(this)) - cachedBalance;

        return fromAmount;
    }

    function _deposit(
        address fromToken,
        uint256 amountIn,
        uint256 id
    ) internal {
        ERC20(fromToken).safeApprove(EARTHQUAKE_VAULT, amountIn);
        IEarthquake(EARTHQUAKE_VAULT).deposit(id, amountIn, msg.sender); // NOTE: Could take receiver input
    }
}
