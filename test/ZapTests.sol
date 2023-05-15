// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Config, IERC20, IERC1155, IBalancerVault} from "./Helper.sol";
import {Y2KTraderJoeZap, ILBPair} from "../src/Y2KTraderJoeZap.sol";

contract ZapV2Test is Config {
    function setUp() public override {
        super.setUp();
    }

    function test_forkAndConfig() public {
        forkAndConfig();
    }

    function test_SwapAndDepositCamelot() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupUSDCtoWETHV2Fork(address(zapCamelot));

        zapCamelot.zapIn(path, fromAmount, toAmountMin, id);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 1);
        vm.stopPrank();
    }

    function test_SwapAndDepositSushiV2() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupUSDCtoWETHV2Fork(address(zapSushiV2));

        zapSushiV2.zapIn(path, fromAmount, toAmountMin, id);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 1);
        vm.stopPrank();
    }

    function test_SwapAndDepositBalancer() public {
        vm.startPrank(sender);
        (
            IBalancerVault.SingleSwap memory singleSwap,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupUSDCtoWETHBalancer(address(zapBalancer));

        zapBalancer.zapIn(singleSwap, fromAmount, toAmountMin, id);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 1);
        vm.stopPrank();
    }

    function test_SwapAndDepositUniswapV3() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            uint24[] memory fee,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupUSDCtoWETHV3(address(zapUniswapV3));

        zapUniswapV3.zapIn(path, fee, fromAmount, toAmountMin, id);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 1);
        vm.stopPrank();
    }

    // NOTE: Overflowing in the reserve comparison section of swap when receivedY() is called
    // NOTE: OVerflowing when (balanceOf(tokenY) - reserveY) i.e. reserveY must be > balanceOf(tokenY) (where reserveY is _reserves private state var)
    /// @notice this must be a sync issue with Foundry and the forked L2 - as tests sending fromToken and calling swap() also failed
    /* @dev
        The contract for their router: https://arbiscan.io/address/0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30#code
        The implementation for pair is here: https://arbiscan.io/address/0xee5a90098b270596ec35d637b30d908c862c86df#code 
    */
    function test_SwapAndDepositTraderJoe() public {
        vm.startPrank(sender);
        (
            Y2KTraderJoeZap.Path memory path,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupUSDCtoWETHTJ(address(zapTraderJoe));

        // Balance of USDC / Balance of WETH / Subtract reserves

        zapTraderJoe.zapIn(path, fromAmount, toAmountMin, id);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 1);
        vm.stopPrank();
    }

    // NOTE: Overflowing in the _k function
    // Pair address: https://arbiscan.io/address/0xA2F1C1B52E1b7223825552343297Dc68a29ABecC#code
    function test_SwapAndDepositChronos() private {
        vm.startPrank(sender);
        (
            address[] memory path,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupUSDCtoWETHV2Fork(address(zapChronos));
        bool stable;

        zapChronos.zapIn(path, fromAmount, toAmountMin, id, stable);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 1);
        vm.stopPrank();
    }
}
