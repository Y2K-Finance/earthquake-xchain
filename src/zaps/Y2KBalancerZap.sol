// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IBalancerVault} from "../interfaces/dexes/IBalancerVault.sol";
import {IEarthquake} from "../interfaces/IEarthquake.sol";
import {IErrors} from "../interfaces/IErrors.sol";
import {ISignatureTransfer} from "../interfaces/ISignatureTransfer.sol";
import {IPermit2} from "../interfaces/IPermit2.sol";

/// @title Balancer Zap for Y2K Vaults
/// @notice Tokens can be swapped on Balancer and deposited into Y2K vaults
contract Y2KBalancerZap is IErrors, ISignatureTransfer {
    using SafeTransferLib for ERC20;
    IBalancerVault public immutable balancerVault;
    IPermit2 public immutable permit2;

    /** @notice constructor
        @param _balancerVault The address of the Balancer vault
        @param _permit2 The address of the permit2 contract
    **/
    constructor(address _balancerVault, address _permit2) {
        if (_balancerVault == address(0)) revert InvalidInput();
        if (_permit2 == address(0)) revert InvalidInput();
        balancerVault = IBalancerVault(_balancerVault);
        permit2 = IPermit2(_permit2);
    }

    /** @notice Single swap tokens on Balancer and deposits them into a Y2K vault
        @param singleSwap The swap struct for the Balancer swap
        @param fromAmount The amount of from token to swap
        @param toAmountMin The minimum amount of tokens to receive from the swap
        @param id The ID of the Y2K vault to deposit into
        @param vaultAddress The address of the Y2K vault to deposit into
        @param receiver The address to receive the Y2K vault shares
    **/
    function zapIn(
        IBalancerVault.SingleSwap calldata singleSwap,
        uint256 fromAmount,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress,
        address receiver
    ) external {
        ERC20(singleSwap.assetIn).safeTransferFrom(
            msg.sender,
            address(this),
            fromAmount
        );
        ERC20(singleSwap.assetIn).safeApprove(
            address(balancerVault),
            fromAmount
        );
        uint256 amountOut = balancerVault.swap(
            singleSwap,
            IBalancerVault.Funds({
                sender: address(this),
                fromInternalBalance: false,
                recipient: address(this),
                toInternalBalance: false
            }),
            toAmountMin,
            block.timestamp + 60 * 15
        );
        _deposit(singleSwap.assetOut, id, amountOut, vaultAddress, receiver);
    }

    /** @notice Single swap tokens on Balancer using permit and deposits them into a Y2K vault
        @param singleSwap The swap struct for the Balancer swap
        @param toAmountMin The minimum amount of tokens to receive from the swap
        @param id The ID of the Y2K vault to deposit into
        @param vaultAddress The address of the Y2K vault to deposit into
        @param receiver The address to receive the Y2K vault shares
        @param permit The permit struct for the token being permitted plus a nonce and deadline
        @param transferDetails Struct with recipient address and amount for transfer
        @param sig The signed permit message
    **/
    function zapInPermit(
        IBalancerVault.SingleSwap calldata singleSwap,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress,
        address receiver,
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) external {
        permit2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        ERC20(permit.permitted.token).safeApprove(
            address(balancerVault),
            transferDetails.requestedAmount
        );
        uint256 amountOut = balancerVault.swap(
            singleSwap,
            IBalancerVault.Funds({
                sender: address(this),
                fromInternalBalance: false,
                recipient: address(this),
                toInternalBalance: false
            }),
            toAmountMin,
            permit.deadline
        );
        _deposit(singleSwap.assetOut, id, amountOut, vaultAddress, receiver);
    }

    /** @notice Multi swap tokens on Balancer and deposits them into a Y2K vault
        @param kind The swap kind for the Balancer swap
        @param swaps The array of swap steps for each swap
        @param assets The array of addresses for the tokens to swap
        @param limits The limits array with an amountIn, zeroed values for amount out, and a negative number for the expected amount out
        @param deadline The deadline for the swap
        @param id The ID of the Y2K vault to deposit into
        @param vaultAddress The address of the Y2K vault to deposit into
        @param receiver The address to receive the Y2K vault shares
    **/
    function zapInMulti(
        IBalancerVault.SwapKind kind,
        IBalancerVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        int256[] memory limits,
        uint256 deadline,
        uint256 id,
        address vaultAddress,
        address receiver
    ) external {
        uint256 fromAmount = uint256(limits[0]);
        address fromToken = assets[0];
        ERC20(fromToken).safeTransferFrom(
            msg.sender,
            address(this),
            fromAmount
        );
        ERC20(fromToken).safeApprove(address(balancerVault), fromAmount);
        int256[] memory assetDeltas = balancerVault.batchSwap(
            kind,
            swaps,
            assets,
            IBalancerVault.Fundmanagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(this)),
                toInternalBalance: false
            }),
            limits,
            deadline
        );
        uint256 amountOut = uint256(-assetDeltas[assetDeltas.length - 1]);
        _deposit(
            assets[assets.length - 1],
            id,
            amountOut, // TODO: Could just use deconstructed amountOut as input
            vaultAddress,
            receiver
        );
    }

    /** @notice Multi swap tokens on Balancer using permit and deposits them into a Y2K vault
        @param kind The swap kind for the Balancer swap
        @param swaps The array of swap steps for each swap
        @param assets The array of addresses for the tokens to swap
        @param limits The limits array with an amountIn, zeroed values for amount out, and a negative number for the expected amount out
        @param id The ID of the Y2K vault to deposit into
        @param vaultAddress The address of the Y2K vault to deposit into
        @param receiver The address to receive the Y2K vault shares
        @param permit The permit struct for the token being permitted plus a nonce and deadline
        @param transferDetails Struct with recipient address and amount for transfer
        @param sig The signed permit message
    **/
    function zapInMultiPermit(
        IBalancerVault.SwapKind kind,
        IBalancerVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        int256[] memory limits,
        uint256 id,
        address vaultAddress,
        address receiver,
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) external {
        permit2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        ERC20(permit.permitted.token).safeApprove(
            address(balancerVault),
            transferDetails.requestedAmount
        );
        int256[] memory assetDeltas = balancerVault.batchSwap(
            kind,
            swaps,
            assets,
            IBalancerVault.Fundmanagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(this)),
                toInternalBalance: false
            }),
            limits,
            permit.deadline
        );
        uint256 amountOut = uint256(-assetDeltas[assetDeltas.length - 1]);
        _deposit(
            assets[assets.length - 1],
            id,
            amountOut, // TODO: Could just use deconstructed amountOut as input
            vaultAddress,
            receiver
        );
    }

    /////////////////////////////////////////
    //    INTERNAL & PRIVATE FUNCTIONS     //
    /////////////////////////////////////////
    function _deposit(
        address fromToken,
        uint256 id,
        uint256 amountIn,
        address vaultAddress,
        address receiver
    ) private {
        ERC20(fromToken).safeApprove(vaultAddress, amountIn);
        IEarthquake(vaultAddress).deposit(id, amountIn, receiver);
    }
}
