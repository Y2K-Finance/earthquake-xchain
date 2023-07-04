// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IErrors} from "../../interfaces/IErrors.sol";
import {ICurvePair} from "../../interfaces/dexes/ICurvePair.sol";

contract CurveSwapper is IErrors {
    using SafeTransferLib for ERC20;
    address payable immutable wethAddress;

    /** @notice Invoked in SwapController constructor
        @param _wethAddress The weth address
    **/
    constructor(address _wethAddress) {
        if (_wethAddress == address(0)) revert InvalidInput();
        wethAddress = payable(_wethAddress);
    }

    /** @notice Decodes the payload and routes to swap, swapEth, or multiswap depending on swapType
        @param payload The data to decode and pass to the correct function
        @return amountOut The amount of toToken received
    */
    function _swapWithCurve(
        bytes calldata payload
    ) internal returns (uint256 amountOut) {
        bytes1 swapType = abi.decode(payload, (bytes1));
        if (swapType == 0x01) {
            (
                ,
                address fromToken,
                address toToken,
                int128 i,
                int128 j,
                address pool,
                uint256 fromAmount,
                uint256 toAmountMin
            ) = abi.decode(
                    payload,
                    (
                        bytes1,
                        address,
                        address,
                        int128,
                        int128,
                        address,
                        uint256,
                        uint256
                    )
                );
            amountOut = _swap(
                fromToken,
                toToken,
                pool,
                i,
                j,
                fromAmount,
                toAmountMin
            );
            if (amountOut == 0) revert InvalidOutput();
        } else if (swapType == 0x02) {
            (
                ,
                address fromToken,
                address toToken,
                uint256 i,
                uint256 j,
                address pool,
                uint256 fromAmount,
                uint256 toAmountIn
            ) = abi.decode(
                    payload,
                    (
                        bytes1,
                        address,
                        address,
                        uint256,
                        uint256,
                        address,
                        uint256,
                        uint256
                    )
                );
            amountOut = _swapEth(
                fromToken,
                toToken,
                pool,
                i,
                j,
                fromAmount,
                toAmountIn
            );
            if (amountOut == 0) revert InvalidOutput();
        } else if (swapType == 0x03) {
            return zapInMulti(payload);
        } else revert InvalidInput();
    }

    /** 
        @notice Decodes the payload and calls multiswap
        @dev Logic abstracted to avoid stack too deep errors in _swapWithCurve
        @param payload The data to decode and pass to multiSwap
    **/
    function zapInMulti(bytes calldata payload) internal returns (uint256) {
        (
            ,
            address[] memory path,
            address[] memory pools,
            uint256[] memory iValues,
            uint256[] memory jValues,
            uint256 fromAmount,
            uint256 toAmountMin
        ) = abi.decode(
                payload,
                (
                    bytes1,
                    address[],
                    address[],
                    uint256[],
                    uint256[],
                    uint256,
                    uint256
                )
            );
        uint256 amountOut = _multiSwap(
            path,
            pools,
            iValues,
            jValues,
            fromAmount,
            toAmountMin
        );
        return amountOut;
    }

    /** @notice Delegates the swap logic for each swap/pair to swapEth or swap
        @param path An array of the tokens being swapped between
        @param pools An array of Curve pools to swap with
        @param iValues An array of indices of the fromToken in each Curve pool
        @param jValues An array of indices of the toToken in each Curve pool
        @param fromAmount The amount of fromToken to swap
        @param toAmountMin The minimum amount of toToken to receive from the swap
        @return amountOut The amount of toToken received from the swap
    **/
    function _multiSwap(
        address[] memory path,
        address[] memory pools,
        uint256[] memory iValues,
        uint256[] memory jValues,
        uint256 fromAmount,
        uint256 toAmountMin
    ) internal returns (uint256 amountOut) {
        amountOut = fromAmount;
        for (uint256 i = 0; i < pools.length; ) {
            if (path[i + 1] != address(0)) {
                amountOut = _swap(
                    path[i],
                    path[i + 1],
                    pools[i],
                    int128(int256(iValues[i])),
                    int128(int256(jValues[i])),
                    amountOut,
                    i == pools.length - 1 ? toAmountMin : 0
                );
            } else {
                amountOut = _swapEth(
                    path[i],
                    wethAddress,
                    pools[i],
                    iValues[i],
                    jValues[i],
                    amountOut,
                    i == pools.length - 1 ? toAmountMin : 0
                );
            }
            unchecked {
                i++;
            }
        }
        if (amountOut == 0) revert InvalidOutput();
    }

    /** @notice Swaps on Curve with the logic for an ERC20 pool 
        @dev Caching the balance are Curve doesn't return amount received
        @param fromToken the token being swapped from
        @param toToken the token being swapped to
        @param pool The Curve pool being swapped with
        @param i The index of the fromToken in the Curve pool
        @param j The index of the toToken in the Curve pool
        @param fromAmount The amount of fromToken to swap
        @param toAmountMin The minimum amount of toToken to receive from the swap
        @return The amount of toToken received from the swap
    **/
    function _swap(
        address fromToken,
        address toToken,
        address pool,
        int128 i,
        int128 j,
        uint256 fromAmount,
        uint256 toAmountMin
    ) private returns (uint256) {
        ERC20(fromToken).safeApprove(pool, fromAmount);
        uint256 cachedBalance = ERC20(toToken).balanceOf(address(this));
        ICurvePair(pool).exchange(i, j, fromAmount, toAmountMin);
        fromAmount = ERC20(toToken).balanceOf(address(this)) - cachedBalance;

        return fromAmount;
    }

    /** @notice Swaps on Curve with the logic for an ETH pool 
        @dev Caching the balance are Curve doesn't return amount received
        @param fromToken the token being swapped from
        @param toToken the token being swapped to
        @param pool The Curve pool being swapped with
        @param i The index of the fromToken in the Curve pool
        @param j The index of the toToken in the Curve pool
        @param fromAmount The amount of fromToken to swap
        @param toAmountMin The minimum amount of toToken to receive from the swap
        @return The amount of toToken received from the swap
    **/
    function _swapEth(
        address fromToken,
        address toToken,
        address pool,
        uint256 i,
        uint256 j,
        uint256 fromAmount,
        uint256 toAmountMin
    ) private returns (uint256) {
        ERC20(fromToken).safeApprove(pool, fromAmount);
        uint256 cachedBalance = ERC20(toToken).balanceOf(address(this));
        ICurvePair(pool).exchange(i, j, fromAmount, toAmountMin, false);
        fromAmount = ERC20(toToken).balanceOf(address(this)) - cachedBalance;

        return fromAmount;
    }
}
