// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IBalancerVault} from "../interfaces/dexes/IBalancerVault.sol";
import {IEarthquake} from "../interfaces/IEarthquake.sol";
import {IErrors} from "../interfaces/IErrors.sol";
import {ISignatureTransfer} from "../interfaces/ISignatureTransfer.sol";
import {IPermit2} from "../interfaces/IPermit2.sol";

contract Y2KBalancerZap is IErrors, ISignatureTransfer {
    using SafeTransferLib for ERC20;
    IBalancerVault public immutable BALANCER_VAULT;
    address public immutable EARTHQUAKE_VAULT;
    IPermit2 public immutable PERMIT_2;

    constructor(
        address _balancerVault,
        address _earthquakeVault,
        address _permit2
    ) {
        if (_balancerVault == address(0)) revert InvalidInput();
        if (_earthquakeVault == address(0)) revert InvalidInput();
        if (_permit2 == address(0)) revert InvalidInput();
        BALANCER_VAULT = IBalancerVault(_balancerVault);
        EARTHQUAKE_VAULT = _earthquakeVault;
        PERMIT_2 = IPermit2(_permit2);
    }

    function zapIn(
        IBalancerVault.SingleSwap calldata singleSwap,
        uint256 fromAmount,
        uint256 toAmountMin,
        uint256 id
    ) external {
        ERC20(singleSwap.assetIn).safeTransferFrom(
            msg.sender,
            address(this),
            fromAmount
        );
        ERC20(singleSwap.assetIn).safeApprove(
            address(BALANCER_VAULT),
            fromAmount
        );
        uint256 amountOut = BALANCER_VAULT.swap(
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
        _deposit(singleSwap.assetOut, id, amountOut);
    }

    function zapInPermit(
        IBalancerVault.SingleSwap calldata singleSwap,
        uint256 toAmountMin,
        uint256 id,
        PermitTransferFrom memory permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) external {
        PERMIT_2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        ERC20(permit.permitted.token).safeApprove(
            address(BALANCER_VAULT),
            transferDetails.requestedAmount
        );
        uint256 amountOut = BALANCER_VAULT.swap(
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
        _deposit(singleSwap.assetOut, id, amountOut);
    }

    function zapInMulti(
        IBalancerVault.SwapKind kind,
        IBalancerVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        int256[] memory limits,
        uint256 deadline,
        uint256 id
    ) external {
        uint256 fromAmount = uint256(limits[0]);
        address fromToken = assets[0];
        ERC20(fromToken).safeTransferFrom(
            msg.sender,
            address(this),
            fromAmount
        );
        ERC20(fromToken).safeApprove(address(BALANCER_VAULT), fromAmount);
        int256[] memory assetDeltas = BALANCER_VAULT.batchSwap(
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
        // TODO: Confirm the last delta is always the amountOut
        uint256 amountOut = uint256(-assetDeltas[assetDeltas.length - 1]);
        _deposit(assets[assets.length - 1], id, amountOut);
    }

    function zapInMultiPermit(
        IBalancerVault.SwapKind kind,
        IBalancerVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        int256[] memory limits,
        uint256 id,
        PermitTransferFrom memory permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) external {
        PERMIT_2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        ERC20(permit.permitted.token).safeApprove(
            address(BALANCER_VAULT),
            transferDetails.requestedAmount
        );
        int256[] memory assetDeltas = BALANCER_VAULT.batchSwap(
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
        // TODO: Confirm the last delta is always the amountOut
        uint256 amountOut = uint256(-assetDeltas[assetDeltas.length - 1]);
        _deposit(assets[assets.length - 1], id, amountOut);
    }

    /////////////////////////////////////////
    //    INTERNAL & PRIVATE FUNCTIONS     //
    /////////////////////////////////////////
    function _deposit(address fromToken, uint256 id, uint256 amountIn) private {
        ERC20(fromToken).safeApprove(EARTHQUAKE_VAULT, amountIn);
        IEarthquake(EARTHQUAKE_VAULT).deposit(id, amountIn, msg.sender); // NOTE: Could take receiver input
    }
}
