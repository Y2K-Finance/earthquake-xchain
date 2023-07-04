// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IEarthquake} from "../interfaces/IEarthquake.sol";
import {IErrors} from "../interfaces/IErrors.sol";
import {ICurvePair} from "../interfaces/dexes/ICurvePair.sol";
import {ISignatureTransfer} from "../interfaces/ISignatureTransfer.sol";
import {IPermit2} from "../interfaces/IPermit2.sol";

/// @title Curve Zap for Y2K Vaults
/// @notice Tokens can be swapped on Curve and deposited into Y2K vaults
contract Y2KCurveZap is IErrors, ISignatureTransfer {
    using SafeTransferLib for ERC20;
    address public immutable wethAddress;
    IPermit2 public immutable permit2;

    // NOTE: Inputs for permitMulti need to be struct to avoid stack too deep
    struct MultiSwapInfo {
        address[] path;
        address[] pools;
        uint256[] iValues;
        uint256[] jValues;
        uint256 toAmountMin;
        address vaultAddress;
        address receiver;
    }

    /** @notice constructor
        @param _wethAddress The weth address
        @param _permit2 The address of the permit2 contract
    **/
    constructor(address _wethAddress, address _permit2) {
        if (_wethAddress == address(0)) revert InvalidInput();
        if (_permit2 == address(0)) revert InvalidInput();
        wethAddress = _wethAddress;
        permit2 = IPermit2(_permit2);
    }

    /** @notice Single swap tokens on Curve and deposit into Y2K vault
        @param fromToken the token to swap from
        @param toToken the token to swap to
        @param i the index of the from token in the Curve pool
        @param j the index of the to token in the Curve pool
        @param pool the Curve pool to swap on
        @param fromAmount the amount of from token to swap
        @param toAmountMin the minimum amount of tokens to receive from the swap
        @param id The ID of the Y2K vault to deposit into
        @param vaultAddress The address of the Y2K vault to deposit into
        @param receiver The address to receive the Y2K vault shares
    **/
    function zapIn(
        address fromToken,
        address toToken,
        uint256 i,
        uint256 j,
        address pool,
        uint256 fromAmount,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress,
        address receiver
    ) external payable {
        ERC20(fromToken).safeTransferFrom(
            msg.sender,
            address(this),
            fromAmount
        );
        uint256 amountOut;
        if (toToken == wethAddress) {
            amountOut = _swapEth(
                fromToken,
                toToken,
                pool,
                i,
                j,
                fromAmount,
                toAmountMin
            );
        } else {
            amountOut = _swap(
                fromToken,
                toToken,
                pool,
                int128(int256(i)),
                int128(int256(j)),
                fromAmount,
                toAmountMin
            );
        }
        if (amountOut == 0) revert InvalidOutput();
        _deposit(toToken, amountOut, id, vaultAddress, receiver);
    }

    /** @notice Single swap tokens on Curve using permit and deposit into Y2K vault
        @param toToken the token to swap to
        @param i The index of the from token in the Curve pool
        @param j The index of the to token in the Curve pool
        @param pool The Curve pool to swap on
        @param toAmountMin the minimum amount of tokens to receive from the swap
        @param id The ID of the Y2K vault to deposit into
        @param vaultAddress The address of the Y2K vault to deposit into
        @param receiver The address to receive the Y2K vault shares
        @param permit The permit struct for the token being permitted plus a nonce and deadline
        @param transferDetails Struct with recipient address and amount for transfer
        @param sig The signed permit message
    **/
    function zapInPermit(
        address toToken,
        uint256 i,
        uint256 j,
        address pool,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress,
        address receiver,
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) external {
        permit2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        uint256 amountOut;
        if (toToken == wethAddress) {
            amountOut = _swapEth(
                permit.permitted.token,
                toToken,
                pool,
                i,
                j,
                transferDetails.requestedAmount,
                toAmountMin
            );
        } else {
            amountOut = _swap(
                permit.permitted.token,
                toToken,
                pool,
                int128(int256(i)),
                int128(int256(j)),
                transferDetails.requestedAmount,
                toAmountMin
            );
        }
        if (amountOut == 0) revert InvalidOutput();
        _deposit(toToken, amountOut, id, vaultAddress, receiver);
    }

    /** @notice Multi swap tokens on Curve and deposit into Y2K vault
        @param fromAmount the amount of from token to swap
        @param multiSwapInfo Struct containing all the information needed to perform the multi swap
        @param id The ID of the Y2K vault to deposit into
    **/
    function zapInMulti(
        uint256 fromAmount,
        uint256 id,
        MultiSwapInfo calldata multiSwapInfo
    ) external {
        ERC20(multiSwapInfo.path[0]).safeTransferFrom(
            msg.sender,
            address(this),
            fromAmount
        );
        uint256 amountOut = _multiSwap(
            multiSwapInfo.path,
            multiSwapInfo.pools,
            multiSwapInfo.iValues,
            multiSwapInfo.jValues,
            fromAmount,
            multiSwapInfo.toAmountMin
        );
        _deposit(
            multiSwapInfo.path[multiSwapInfo.path.length - 1],
            amountOut,
            id,
            multiSwapInfo.vaultAddress,
            multiSwapInfo.receiver
        );
    }

    /** @notice Multi swap tokens on Curve using permit and deposit into Y2K vault
        @param id The ID of the Y2K vault to deposit into
        @param multiSwapInfo Struct containing all the information needed to perform the multi swap
        @param permit The permit struct for the token being permitted plus a nonce and deadline
        @param transferDetails Struct with recipient address and amount for transfer
        @param sig The signed permit message
    **/
    function zapInMultiPermit(
        uint256 id,
        MultiSwapInfo calldata multiSwapInfo,
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) external {
        permit2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        uint256 amountOut = _multiSwap(
            multiSwapInfo.path,
            multiSwapInfo.pools,
            multiSwapInfo.iValues,
            multiSwapInfo.jValues,
            transferDetails.requestedAmount,
            multiSwapInfo.toAmountMin
        );
        _deposit(
            multiSwapInfo.path[multiSwapInfo.path.length - 1],
            amountOut,
            id,
            multiSwapInfo.vaultAddress,
            multiSwapInfo.receiver
        );
    }

    /////////////////////////////////////////
    //    INTERNAL & PRIVATE FUNCTIONS     //
    /////////////////////////////////////////
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
    ) private returns (uint256 amountOut) {
        amountOut = fromAmount;
        for (uint256 i = 0; i < pools.length; ) {
            if (path[i + 1] != wethAddress) {
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

    /** @notice Deposits fromToken into a Y2K vault
        @param fromToken The ERC20 token being deposited to the vault
        @param id The ID of the Y2K vault to deposit into the vault
        @param amountIn The amount of fromToken being deposited to the vault
        @param vaultAddress The address of the Y2K vault to deposit into
        @param receiver The address to receive the Y2K vault shares
    **/
    function _deposit(
        address fromToken,
        uint256 amountIn,
        uint256 id,
        address vaultAddress,
        address receiver
    ) private {
        ERC20(fromToken).safeApprove(vaultAddress, amountIn);
        IEarthquake(vaultAddress).deposit(id, amountIn, receiver);
    }
}
