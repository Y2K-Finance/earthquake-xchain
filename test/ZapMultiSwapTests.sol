// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Config, IERC20} from "./utils/Helper.sol";
import {IERC1155} from "./utils/Interfaces.sol";
import {Y2KTraderJoeZap, ILBPair} from "../src//zaps/Y2KTraderJoeZap.sol";
import {IBalancerVault} from "../src/interfaces/dexes/IBalancerVault.sol";

contract ZapSwapMultiTest is Config {
    function test_MultiswapAndDepositCamelot() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupUSDCtoUSDTtoWETHV2Fork(address(zapCamelot));

        zapCamelot.zapIn(path, fromAmount, toAmountMin, id);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 1);
        vm.stopPrank();
    }

    function test_Multiswap3xAndDepositCamelot() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupDAItoUSDCtoUSDTtoWETHV2Fork(address(zapCamelot));

        zapCamelot.zapIn(path, fromAmount, toAmountMin, id);
        assertEq(IERC20(DAI_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 1);
        vm.stopPrank();
    }

    function test_MultiswapAndDepositSushiV2() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupUSDCtoUSDTtoWETHV2Fork(address(zapSushiV2));

        zapSushiV2.zapIn(path, fromAmount, toAmountMin, id);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 1);
        vm.stopPrank();
    }

    function test_Multiswap3xAndDepositSushiV2() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupWETHtoUSDCtoUSDTtoWETHV2Fork(address(zapSushiV2));

        zapSushiV2.zapIn(path, fromAmount, toAmountMin, id);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 1);
        vm.stopPrank();
    }

    function test_MultiswapAndDepositUniswapV3() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            uint24[] memory fee,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupUSDCtoUSDTtoWETHV3(address(zapUniswapV3));

        zapUniswapV3.zapIn(path, fee, fromAmount, toAmountMin, id);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 1);
        vm.stopPrank();
    }

    function test_Multiswap3xAndDepositUniswapV3() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            uint24[] memory fee,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupDAItoUSDCtoUSDTtoWETHV3(address(zapUniswapV3));

        zapUniswapV3.zapIn(path, fee, fromAmount, toAmountMin, id);
        assertEq(IERC20(DAI_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 1);
        vm.stopPrank();
    }

    // 521 error - should relate to the token not being registered
    function test_MultiswapAndDepositBalancer() public {
        vm.startPrank(sender);
        (
            IBalancerVault.SwapKind kind,
            IBalancerVault.BatchSwapStep[] memory batchSwap,
            address[] memory assets,
            int256[] memory limits,
            uint256 deadline,
            uint256 id
        ) = setupUSDTtoUSDCtoWETHBalancer(address(zapBalancer));

        zapBalancer.zapInMulti(kind, batchSwap, assets, limits, deadline, id);
        assertEq(IERC20(USDT_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 1);
        vm.stopPrank();
    }

    function test_Multiswap3xAndDepositBalancer() public {
        vm.startPrank(sender);
        (
            IBalancerVault.SwapKind kind,
            IBalancerVault.BatchSwapStep[] memory batchSwap,
            address[] memory assets,
            int256[] memory limits,
            uint256 deadline,
            uint256 id
        ) = setupDUSDtoUSDTtoUSDCtoWETHBalancer(address(zapBalancer));

        zapBalancer.zapInMulti(kind, batchSwap, assets, limits, deadline, id);
        assertEq(IERC20(DUSD_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 1);
        vm.stopPrank();
    }

    function test_MultiswapAndDepositCurve() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            address[] memory pools,
            uint256[] memory iValues,
            uint256[] memory jValues,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupUSDCtoUSDTtoWETHCurve(
                address(zapCurveUSDT),
                EARTHQUAKE_VAULT_USDT
            );

        zapCurveUSDT.zapInMulti(
            path,
            pools,
            iValues,
            jValues,
            fromAmount,
            toAmountMin,
            id
        );
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT_USDT).balanceOf(sender, id), 1);
        vm.stopPrank();
    }

    function test_Multiswap3xAndDepositCurve() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            address[] memory pools,
            uint256[] memory iValues,
            uint256[] memory jValues,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupFRAXtoUSDCtoUSDTtoWETHCurve(
                address(zapCurveUSDT),
                EARTHQUAKE_VAULT_USDT
            );

        zapCurveUSDT.zapInMulti(
            path,
            pools,
            iValues,
            jValues,
            fromAmount,
            toAmountMin,
            id
        );
        assertEq(IERC20(FRAX_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT_USDT).balanceOf(sender, id), 1);
        vm.stopPrank();
    }

    function test_MultiswapAndDepositGMX() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupUSDCtoUSDTtoWETHV2Fork(address(zapGMX)); // NOTE: Uses the same inputs as V2 forks

        zapGMX.zapIn(path, fromAmount, toAmountMin, id);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 1);
        vm.stopPrank();
    }
}
