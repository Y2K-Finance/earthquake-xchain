// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../../test/utils/Helper.sol";
import {Y2KCamelotZap} from "../../src//zaps/Y2KCamelotZap.sol";
import {Y2KUniswapV2Zap} from "../../src//zaps/Y2KUniswapV2Zap.sol";
import {Y2KBalancerZap} from "../../src//zaps/Y2KBalancerZap.sol";
import {Y2KUniswapV3Zap} from "../../src//zaps/Y2KUniswapV3Zap.sol";
import {Y2KCurveZap} from "../../src//zaps/Y2KCurveZap.sol";
import {Y2KGMXZap} from "../../src//zaps/Y2KGMXZap.sol";
import {IBalancerVault} from "../../src/interfaces/dexes/IBalancerVault.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract ZapHelper is Script, Helper {
    address public liveSender = 0x2d244ed7d17AE47886f7f13F53e74b6B0bC16fdC; // Y2K Deployer
    address public liveReceiver = 0x9EF27dB2778690edf94632F1C57d0Bd2fDAadd7f; // Y2K Tester
    address public vaultAddress;
    uint256 public epochId;
    uint256 public dexId;

    address public camelotZapper = address(0x123);
    address public balancerZapper = address(0x123);
    address public gmxZapper = address(0x123);
    address public curveZapper = address(0x123);
    address public sushiZapper = address(0x123);
    address public uniswapV3Zapper = address(0x123);

    Y2KCamelotZap public zapCamelot;
    Y2KBalancerZap public zapBalancer;
    Y2KGMXZap public zapGMX;
    Y2KCurveZap public zapCurve;
    Y2KUniswapV2Zap public zapSushiV2;
    Y2KUniswapV3Zap public zapUniswapV3;

    /////////////////////////////////////////
    //          DEX CONFIGS             //
    /////////////////////////////////////////
    function setupUSDCtoWETHV2Fork(
        address wrapperAddress
    ) public returns (address[] memory path, uint256, uint256, uint256) {
        path = new address[](2);
        path[0] = USDC_ADDRESS;
        path[1] = WETH_ADDRESS;
        uint256 fromAmount = 5_000_000;
        uint256 toAmountMin = 24_000_000_000_000_000;
        uint256 id = EPOCH_ID;

        if (
            IERC20(USDC_ADDRESS).allowance(liveSender, wrapperAddress) <
            fromAmount
        ) IERC20(USDC_ADDRESS).approve(address(wrapperAddress), fromAmount);
        return (path, fromAmount, toAmountMin, id);
    }

    function setupUSDCtoWETHBalancer(
        address wrapperAddress
    )
        public
        returns (
            IBalancerVault.SingleSwap memory singleSwap,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 fromAmount = 5_000_000;
        uint256 toAmountMin = 24_000_000_000_000_000;
        uint256 id = 1684713600;

        singleSwap.amount = fromAmount;
        singleSwap.assetIn = USDC_ADDRESS;
        singleSwap.assetOut = WETH_ADDRESS;
        singleSwap.kind = 0; // GIVEN_IN
        singleSwap.poolId = USDC_WETH_POOL_ID_BALANCER;
        singleSwap.userData = "";

        if (
            IERC20(USDC_ADDRESS).allowance(liveSender, wrapperAddress) <
            fromAmount
        ) IERC20(USDC_ADDRESS).approve(address(wrapperAddress), fromAmount);
        return (singleSwap, fromAmount, toAmountMin, id);
    }

    function setupUSDCtoWETHV3(
        address wrapperAddress
    )
        public
        returns (
            address[] memory path,
            uint24[] memory fee,
            uint256,
            uint256,
            uint256
        )
    {
        path = new address[](2);
        fee = new uint24[](1);

        path[0] = USDC_ADDRESS;
        path[1] = WETH_ADDRESS;
        fee[0] = 500;
        uint256 fromAmount = 5_000_000;
        uint256 toAmountMin = 24_000_000_000_000_000;
        uint256 id = EPOCH_ID;

        if (
            IERC20(USDC_ADDRESS).allowance(liveSender, wrapperAddress) <
            fromAmount
        ) IERC20(USDC_ADDRESS).approve(address(wrapperAddress), fromAmount);
        return (path, fee, fromAmount, toAmountMin, id);
    }

    function setupUSDTtoWETHCurve(
        address wrapperAddress
    )
        public
        returns (
            address fromToken,
            address toToken,
            uint256 i,
            uint256 j,
            address pool,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        )
    {
        fromToken = USDT_ADDRESS;
        toToken = WETH_ADDRESS;
        i = 0;
        j = 2;
        pool = USDT_WETH_POOL_CURVE;

        fromAmount = 5_000_000;
        toAmountMin = 24_000_000_000_000_000;
        id = EPOCH_ID;

        if (
            IERC20(USDC_ADDRESS).allowance(liveSender, wrapperAddress) <
            fromAmount
        ) IERC20(USDT_ADDRESS).approve(address(wrapperAddress), fromAmount);
    }

    /////////////////////////////////////////
    //          DEX TESTS             //
    /////////////////////////////////////////

    function _testBalancer() internal {
        (
            IBalancerVault.SingleSwap memory singleSwap,
            uint256 fromAmount,
            uint256 toAmountMin,

        ) = setupUSDCtoWETHBalancer(address(zapBalancer));

        zapBalancer.zapIn(
            singleSwap,
            fromAmount,
            toAmountMin,
            epochId,
            vaultAddress,
            liveReceiver
        );
    }

    function _testCamelot() internal {
        (
            address[] memory path,
            uint256 fromAmount,
            uint256 toAmountMin,

        ) = setupUSDCtoWETHV2Fork(address(zapCamelot));

        zapCamelot.zapIn(
            path,
            fromAmount,
            toAmountMin,
            epochId,
            vaultAddress,
            liveReceiver
        );
    }

    function _testCurve() internal {
        (
            address fromToken,
            address toToken,
            uint256 i,
            uint256 j,
            address pool,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupUSDTtoWETHCurve(address(zapCurve));

        zapCurve.zapIn(
            fromToken,
            toToken,
            i,
            j,
            pool,
            fromAmount,
            toAmountMin,
            id,
            vaultAddress,
            liveReceiver
        );
    }

    function _testGMX() internal {
        (
            address[] memory path,
            uint256 fromAmount,
            uint256 toAmountMin,

        ) = setupUSDCtoWETHV2Fork(address(zapGMX));

        zapGMX.zapIn(
            path,
            fromAmount,
            toAmountMin,
            epochId,
            vaultAddress,
            liveReceiver
        );
    }

    function _testSushi() internal {
        (
            address[] memory path,
            uint256 fromAmount,
            uint256 toAmountMin,

        ) = setupUSDCtoWETHV2Fork(address(zapSushiV2));

        zapSushiV2.zapIn(
            path,
            fromAmount,
            toAmountMin,
            epochId,
            vaultAddress,
            liveReceiver
        );
    }

    function _testUniV3() internal {
        (
            address[] memory path,
            uint24[] memory fee,
            uint256 fromAmount,
            uint256 toAmountMin,

        ) = setupUSDCtoWETHV3(address(zapUniswapV3));

        zapUniswapV3.zapIn(
            path,
            fee,
            fromAmount,
            toAmountMin,
            epochId,
            vaultAddress,
            liveReceiver
        );
    }
}
