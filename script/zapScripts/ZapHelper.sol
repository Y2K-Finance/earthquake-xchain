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

    address public camelotZapper = 0x4B4AfB7705c512913f3B9Ba063d8f7EDc1589e4b;
    address public balancerZapper = 0xe56934Fe3D25a8b813CF940884F8E4A743E6EDfC;
    address public gmxZapper = 0xa0FE4F44c29Aa5290BD0dEB281c3355198723bd3;
    address public curveZapper = 0x3C2387fACD81D639736E6aab38D6B135D8604a67;
    address public sushiZapper = 0x3c9abB034a2097AE45658ac513F23fcf90E9f0D7;
    address public uniswapV3Zapper = 0xfd54A7256edf94A06c402709e5227C63952513E7;

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
        uint256 toAmountMin = 2_400_000_000_000_000;
        uint256 id = epochId;

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
        uint256 toAmountMin = 2_400_000_000_000_000;
        uint256 id = epochId;

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
        uint256 toAmountMin = 2_400_000_000_000_000;
        uint256 id = epochId;

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
        toAmountMin = 2_400_000_000_000_000;
        id = epochId;

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
