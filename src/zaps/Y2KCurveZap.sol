// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IEarthquake} from "../interfaces/IEarthquake.sol";
import {IErrors} from "../interfaces/IErrors.sol";
import {ICurvePair} from "../interfaces/dexes/ICurvePair.sol";
import {ISignatureTransfer} from "../interfaces/ISignatureTransfer.sol";
import {IPermit2} from "../interfaces/IPermit2.sol";

contract Y2KCurveZap is IErrors, ISignatureTransfer {
    using SafeTransferLib for ERC20;
    address public immutable WETH_ADDRESS;
    IPermit2 public immutable PERMIT_2;

    constructor(address _wethAddress, address _permit2) {
        if (_wethAddress == address(0)) revert InvalidInput();
        if (_permit2 == address(0)) revert InvalidInput();
        WETH_ADDRESS = _wethAddress;
        PERMIT_2 = IPermit2(_permit2);
    }

    function zapIn(
        address fromToken,
        address toToken,
        uint256 i,
        uint256 j,
        address pool,
        uint256 fromAmount,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress
    ) external payable {
        ERC20(fromToken).safeTransferFrom(
            msg.sender,
            address(this),
            fromAmount
        );
        uint256 amountOut;
        if (toToken == WETH_ADDRESS) {
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
        _deposit(toToken, amountOut, id, vaultAddress);
    }

    function zapInPermit(
        address toToken,
        uint256 i,
        uint256 j,
        address pool,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress,
        PermitTransferFrom memory permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) external {
        PERMIT_2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        uint256 amountOut;
        if (toToken == WETH_ADDRESS) {
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
        _deposit(toToken, amountOut, id, vaultAddress);
    }

    // NOTE: Logic has to be abstract to avoid stack too deep errors
    struct MultiSwapInfo {
        address[] path;
        address[] pools;
        uint256[] iValues;
        uint256[] jValues;
        uint256 toAmountMin;
        address vaultAddress;
    }

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
        if (amountOut == 0) revert InvalidOutput();
        _deposit(
            multiSwapInfo.path[multiSwapInfo.path.length - 1],
            amountOut,
            id,
            multiSwapInfo.vaultAddress
        );
    }

    function zapInMultiPermit(
        uint256 id,
        MultiSwapInfo calldata multiSwapInfo,
        PermitTransferFrom memory permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) external {
        PERMIT_2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        uint256 amountOut = _multiSwap(
            multiSwapInfo.path,
            multiSwapInfo.pools,
            multiSwapInfo.iValues,
            multiSwapInfo.jValues,
            transferDetails.requestedAmount,
            multiSwapInfo.toAmountMin
        );

        if (amountOut == 0) revert InvalidOutput();
        _deposit(
            multiSwapInfo.path[multiSwapInfo.path.length - 1],
            amountOut,
            id,
            multiSwapInfo.vaultAddress
        );
    }

    /////////////////////////////////////////
    //    INTERNAL & PRIVATE FUNCTIONS     //
    /////////////////////////////////////////
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
            if (path[i + 1] != WETH_ADDRESS) {
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
                    WETH_ADDRESS,
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
    }

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

    function _deposit(
        address fromToken,
        uint256 amountIn,
        uint256 id,
        address vaultAddress
    ) private {
        ERC20(fromToken).safeApprove(vaultAddress, amountIn);
        IEarthquake(vaultAddress).deposit(id, amountIn, msg.sender); // NOTE: Could take receiver input
    }
}
