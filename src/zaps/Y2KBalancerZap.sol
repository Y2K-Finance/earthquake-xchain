// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IBalancerVault} from "../interfaces/dexes/IBalancerVault.sol";
import {IEarthquake} from "../interfaces/IEarthquake.sol";
import {IErrors} from "../interfaces/IErrors.sol";

contract Y2KBalancerZap is IErrors {
    using SafeTransferLib for ERC20;
    IBalancerVault public immutable BALANCER_VAULT;
    address public immutable EARTHQUAKE_VAULT;

    constructor(address _balancerVault, address _earthquakeVault) {
        if (_balancerVault == address(0)) revert InvalidInput();
        if (_earthquakeVault == address(0)) revert InvalidInput();
        BALANCER_VAULT = IBalancerVault(_balancerVault);
        EARTHQUAKE_VAULT = _earthquakeVault;
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
        ERC20(singleSwap.assetOut).safeApprove(EARTHQUAKE_VAULT, amountOut);
        IEarthquake(EARTHQUAKE_VAULT).deposit(id, amountOut, msg.sender); // NOTE: Could take receiver input
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
        ERC20(assets[assets.length - 1]).safeApprove(
            EARTHQUAKE_VAULT,
            amountOut
        );
        IEarthquake(EARTHQUAKE_VAULT).deposit(id, amountOut, msg.sender); // NOTE: Could take receiver input
    }
}
