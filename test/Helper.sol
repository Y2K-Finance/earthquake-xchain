// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {Y2KCamelotZap} from "../src/Y2KCamelotZap.sol";
import {Y2KUniswapV2Zap} from "../src/Y2KUniswapV2Zap.sol";
import {Y2KChronosZap} from "../src/Y2KChronosZap.sol";
import {Y2KBalancerZap} from "../src/Y2KBalancerZap.sol";
import {Y2KUniswapV3Zap} from "../src/Y2KUniswapV3Zap.sol";
import {Y2KTraderJoeZap} from "../src/Y2KTraderJoeZap.sol";
import {Y2KCurveZap} from "../src/Y2KCurveZap.sol";
import {Y2KGMXZap} from "../src/Y2KGMXZap.sol";

import {IBalancerVault} from "../src/interfaces/IBalancerVault.sol";
import {IEarthQuakeVault, IERC1155} from "./Interfaces.sol";

abstract contract Helper {
    address constant USDC_ADDRESS = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant USDT_ADDRESS = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant DAI_ADDRESS = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address constant WETH_ADDRESS = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant sender = address(0x01);

    ////////////// DEX & VAULT STATE VARS //////////////
    address constant EARTHQUAKE_VAULT =
        0xb4fbD25A32d21299e356916044D6FbB078016c46;
    address constant EARTHQUAKE_VAULT_USDT =
        0x76b1803530A3608bD5F1e4a8bdaf3007d7d2D7FA;
    address constant EARTHQUAKE_FACTORY =
        0x984E0EB8fB687aFa53fc8B33E12E04967560E092;
    address constant CAMELOT_FACTORY =
        0x6EcCab422D763aC031210895C81787E87B43A652;
    address constant SUSHI_V2_FACTORY =
        0xc35DADB65012eC5796536bD9864eD8773aBc74C4;
    address constant BALANCER_VAULT =
        0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    bytes32 constant USDT_USDC_POOL_ID_BALANCER =
        0x1533a3278f3f9141d5f820a184ea4b017fce2382000000000000000000000016;
    bytes32 constant USDC_WETH_POOL_ID_BALANCER =
        0x64541216bafffeec8ea535bb71fbc927831d0595000100000000000000000002;
    address constant USDC_WETH_POOL_CURVE =
        0x960ea3e3C7FB317332d990873d354E18d7645590;
    address constant GMX_VAULT = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
    address constant CHRONOS_FACTORY =
        0xCe9240869391928253Ed9cc9Bcb8cb98CB5B0722;
    address constant UNISWAP_V3_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant TJ_LEGACY_FACTORY =
        0x1886D09C9Ade0c5DB822D85D21678Db67B6c2982;
    address constant TJ_FACTORY = 0x8e42f2F4101563bF679975178e880FD87d3eFd4e;
    address constant TJ_FACTORY_V1 = 0xaE4EC9901c3076D0DdBe76A520F9E90a6227aCB7;

    ////////////// EARTHQUAKE VAULT STATE VARS //////////////
    address constant EARTHQUAKE_CONTROLLER =
        0x225aCF1D32f0928A96E49E6110abA1fdf777C85f;
    uint256 constant EPOCH_ID = 1684713600;
    uint256 constant EPOCH_BEGIN = 1684281600;
    uint256 constant EPOCH_ID_USDT = 1684713600;
    uint256 constant EPOCH_BEGIN_USDT = 1684281600;
}

contract Config is Test, Helper {
    string public MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string public ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");
    Y2KCamelotZap public zapCamelot;
    Y2KUniswapV2Zap public zapSushiV2;
    Y2KChronosZap public zapChronos;
    Y2KBalancerZap public zapBalancer;
    Y2KUniswapV3Zap public zapUniswapV3;
    Y2KCurveZap public zapCurve;
    Y2KCurveZap public zapCurveUSDT;
    Y2KGMXZap public zapGMX;
    Y2KTraderJoeZap public zapTraderJoe;

    uint256 mainnetFork;
    uint256 arbitrumFork;

    function setUp() public virtual {
        mainnetFork = vm.createSelectFork(MAINNET_RPC_URL, 17269532);
        arbitrumFork = vm.createFork(ARBITRUM_RPC_URL);
        vm.selectFork(arbitrumFork);
        vm.warp(EPOCH_BEGIN - 1);
        // vm.roll(90815015);

        zapCamelot = new Y2KCamelotZap(CAMELOT_FACTORY, EARTHQUAKE_VAULT); // Earthquake Vault | DAI RISK
        zapSushiV2 = new Y2KUniswapV2Zap(SUSHI_V2_FACTORY, EARTHQUAKE_VAULT); // Earthquake Vault | DAI RISK
        zapBalancer = new Y2KBalancerZap(BALANCER_VAULT, EARTHQUAKE_VAULT); // Earthquake Vault | DAI RISK
        zapUniswapV3 = new Y2KUniswapV3Zap(
            UNISWAP_V3_FACTORY,
            EARTHQUAKE_VAULT
        );
        zapCurve = new Y2KCurveZap(EARTHQUAKE_VAULT);
        zapCurveUSDT = new Y2KCurveZap(EARTHQUAKE_VAULT_USDT);
        zapGMX = new Y2KGMXZap(GMX_VAULT, EARTHQUAKE_VAULT);
        zapTraderJoe = new Y2KTraderJoeZap(
            TJ_LEGACY_FACTORY,
            TJ_FACTORY,
            TJ_FACTORY_V1,
            EARTHQUAKE_VAULT
        );

        // NOTE: Need to dynamically provide the INIT CODE HASH and find the factory for Chronos
        zapChronos = new Y2KChronosZap(CHRONOS_FACTORY, EARTHQUAKE_VAULT); // Earthquake Vault | DAI RISK

        vm.label(address(0x01), "Sender");
        vm.label(USDC_ADDRESS, "USDC");
        vm.label(DAI_ADDRESS, "DAI");
        vm.label(WETH_ADDRESS, "WETH");
        vm.label(CAMELOT_FACTORY, "Camelot Factory");
        vm.label(EARTHQUAKE_VAULT, "Earthquake Vault");
        vm.label(EARTHQUAKE_VAULT_USDT, "Earthquake Vault USDT");
        vm.label(address(zapCamelot), "Camelot Zapper");
        vm.label(address(zapSushiV2), "Sushi Zapper");
        vm.label(address(zapChronos), "Chronos Zapper");
        vm.label(address(zapBalancer), "Balancer Zapper");
        vm.label(address(zapUniswapV3), "Uniswap V3 Zapper");
        vm.label(address(zapTraderJoe), "Trader Joe Zapper");
        vm.label(address(zapCurve), "Curve Zapper");
    }

    function forkAndConfig() public {
        assertEq(vm.activeFork(), arbitrumFork);
        assertEq(ERC20(USDC_ADDRESS).symbol(), "USDC");
        assertEq(zapCamelot.EARTHQUAKE_VAULT(), EARTHQUAKE_VAULT);
        assertEq(
            IEarthQuakeVault(EARTHQUAKE_VAULT).controller(),
            EARTHQUAKE_CONTROLLER
        );
        assertEq(
            IEarthQuakeVault(EARTHQUAKE_VAULT).idEpochBegin(EPOCH_ID),
            EPOCH_BEGIN
        );
        assertEq(block.timestamp, EPOCH_BEGIN - 1);
    }

    function setupUSDCtoWETHV2Fork(
        address wrapperAddress
    ) public returns (address[] memory path, uint256, uint256, uint256) {
        deal(USDC_ADDRESS, sender, 10_000_000);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 10e6);

        path = new address[](2);
        path[0] = USDC_ADDRESS;
        path[1] = WETH_ADDRESS;
        uint256 fromAmount = 10_000_000;
        uint256 toAmountMin = 500_000_000_000_000;
        uint256 id = EPOCH_ID;

        bool approved = IERC20(USDC_ADDRESS).approve(
            address(wrapperAddress),
            fromAmount
        );
        assertEq(approved, true);
        assertEq(
            IERC20(USDC_ADDRESS).allowance(sender, address(wrapperAddress)),
            fromAmount
        );
        assertEq(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 0);
        return (path, fromAmount, toAmountMin, id);
    }

    function setupUSDCtoUSDTtoWETHV2Fork(
        address wrapperAddress
    ) public returns (address[] memory path, uint256, uint256, uint256) {
        deal(USDC_ADDRESS, sender, 10_000_000);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 10e6);

        path = new address[](3);
        path[0] = USDC_ADDRESS;
        path[1] = USDT_ADDRESS;
        path[2] = WETH_ADDRESS;
        uint256 fromAmount = 10_000_000;
        uint256 toAmountMin = 500_000_000_000_000;
        uint256 id = EPOCH_ID;

        bool approved = IERC20(USDC_ADDRESS).approve(
            address(wrapperAddress),
            fromAmount
        );
        assertEq(approved, true);
        assertEq(
            IERC20(USDC_ADDRESS).allowance(sender, address(wrapperAddress)),
            fromAmount
        );
        assertEq(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 0);
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
        deal(USDC_ADDRESS, sender, 10_000_000);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 10e6);

        uint256 fromAmount = 10_000_000;
        uint256 toAmountMin = 500_000_000_000_000;
        uint256 id = 1684713600;

        singleSwap.amount = fromAmount;
        singleSwap.assetIn = USDC_ADDRESS;
        singleSwap.assetOut = WETH_ADDRESS;
        singleSwap.kind = 0; // GIVEN_IN
        singleSwap.poolId = USDC_WETH_POOL_ID_BALANCER;
        singleSwap.userData = "";

        bool approved = IERC20(USDC_ADDRESS).approve(
            address(wrapperAddress),
            fromAmount
        );
        assertEq(approved, true);
        assertEq(
            IERC20(USDC_ADDRESS).allowance(sender, address(wrapperAddress)),
            fromAmount
        );
        assertEq(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 0);

        return (singleSwap, fromAmount, toAmountMin, id);
    }

    function setupUSDTtoUSDCtoWETHBalancer(
        address wrapperAddress
    )
        public
        returns (
            IBalancerVault.SwapKind kind,
            IBalancerVault.BatchSwapStep[] memory batchSwap,
            address[] memory assets,
            int256[] memory limits,
            uint256 deadline,
            uint256 id
        )
    {
        deal(USDT_ADDRESS, sender, 10_000_000);
        assertEq(IERC20(USDT_ADDRESS).balanceOf(sender), 10e6);

        uint256 fromAmount = 10_000_000;
        uint256 toAmountMin = 500_000_000_000_000;
        id = 1684713600;
        kind = IBalancerVault.SwapKind.GIVEN_IN;

        batchSwap = new IBalancerVault.BatchSwapStep[](2);
        batchSwap[0].poolId = USDT_USDC_POOL_ID_BALANCER;
        batchSwap[0].assetInIndex = 2;
        batchSwap[0].assetOutIndex = 1;
        batchSwap[0].amount = fromAmount;
        batchSwap[0].userData = bytes("");
        batchSwap[1].poolId = USDC_WETH_POOL_ID_BALANCER;
        batchSwap[1].assetInIndex = 0;
        batchSwap[1].assetOutIndex = 1;
        batchSwap[1].amount = 0;
        batchSwap[1].userData = bytes("");

        assets = new address[](3);
        assets[0] = USDT_ADDRESS;
        assets[1] = USDC_ADDRESS;
        assets[2] = WETH_ADDRESS;

        limits = new int256[](3);
        limits[0] = int256(fromAmount);
        limits[1] = 0;
        limits[2] = int256(toAmountMin) - (2 * int256(toAmountMin));

        deadline = block.timestamp + 3600;

        bool approved = IERC20(USDT_ADDRESS).approve(
            address(wrapperAddress),
            fromAmount
        );
        assertEq(approved, true);
        assertEq(
            IERC20(USDT_ADDRESS).allowance(sender, address(wrapperAddress)),
            fromAmount
        );
        assertEq(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 0);

        return (kind, batchSwap, assets, limits, deadline, id);
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
        deal(USDC_ADDRESS, sender, 10_000_000);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 10e6);

        path = new address[](2);
        fee = new uint24[](1);

        path[0] = USDC_ADDRESS;
        path[1] = WETH_ADDRESS;
        fee[0] = 500;
        uint256 fromAmount = 10_000_000;
        uint256 toAmountMin = 500_000_000_000_000;
        uint256 id = EPOCH_ID;

        bool approved = IERC20(USDC_ADDRESS).approve(
            address(wrapperAddress),
            fromAmount
        );
        assertEq(approved, true);
        assertEq(
            IERC20(USDC_ADDRESS).allowance(sender, address(wrapperAddress)),
            fromAmount
        );
        assertEq(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 0);
        return (path, fee, fromAmount, toAmountMin, id);
    }

    function setupUSDCtoUSDTtoWETHV3(
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
        deal(USDC_ADDRESS, sender, 10_000_000);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 10e6);

        path = new address[](3);
        fee = new uint24[](2);

        path[0] = USDC_ADDRESS;
        path[1] = USDT_ADDRESS;
        path[2] = WETH_ADDRESS;
        fee[0] = 100;
        fee[1] = 500;
        uint256 fromAmount = 10_000_000;
        uint256 toAmountMin = 500_000_000_000_000;
        uint256 id = EPOCH_ID;

        bool approved = IERC20(USDC_ADDRESS).approve(
            address(wrapperAddress),
            fromAmount
        );
        assertEq(approved, true);
        assertEq(
            IERC20(USDC_ADDRESS).allowance(sender, address(wrapperAddress)),
            fromAmount
        );
        assertEq(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 0);
        return (path, fee, fromAmount, toAmountMin, id);
    }

    function setupUSDTtoWETHCurve(
        address wrapperAddress,
        address vaultAddress
    )
        public
        returns (
            address fromToken,
            address toToken,
            int128 i,
            int128 j,
            address pool,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        )
    {
        deal(USDT_ADDRESS, sender, 10_000_000);
        assertEq(IERC20(USDT_ADDRESS).balanceOf(sender), 10e6);

        fromToken = USDT_ADDRESS;
        toToken = WETH_ADDRESS;
        i = 0;
        j = 2;
        pool = USDC_WETH_POOL_CURVE;

        fromAmount = 10_000_000;
        toAmountMin = 500_000_000_000_000;
        id = EPOCH_ID;

        bool approved = IERC20(USDT_ADDRESS).approve(
            address(wrapperAddress),
            fromAmount
        );
        assertEq(approved, true);
        assertEq(
            IERC20(USDT_ADDRESS).allowance(sender, address(wrapperAddress)),
            fromAmount
        );
        assertEq(IERC1155(vaultAddress).balanceOf(sender, id), 0);
    }

    function setupUSDCtoUSDTtoWETHCurve(
        address wrapperAddress,
        address vaultAddress
    )
        public
        returns (
            address fromToken,
            address toToken,
            int128 i,
            int128 j,
            address pool,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        )
    {
        deal(USDC_ADDRESS, sender, 10_000_000);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 10e6);

        fromToken = USDC_ADDRESS;
        toToken = WETH_ADDRESS;
        i = 0;
        j = 2;
        pool = USDC_WETH_POOL_CURVE;

        fromAmount = 10_000_000;
        toAmountMin = 500_000_000_000_000;
        id = EPOCH_ID;

        bool approved = IERC20(USDC_ADDRESS).approve(
            address(wrapperAddress),
            fromAmount
        );
        assertEq(approved, true);
        assertEq(
            IERC20(USDC_ADDRESS).allowance(sender, address(wrapperAddress)),
            fromAmount
        );
        assertEq(IERC1155(vaultAddress).balanceOf(sender, id), 0);
    }

    function setupUSDCtoWETHTJ(
        address wrapperAddress
    )
        public
        returns (Y2KTraderJoeZap.Path memory path, uint256, uint256, uint256)
    {
        deal(USDC_ADDRESS, sender, 100_000_000);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 100e6);

        path.pairBinSteps = new uint256[](1);
        path.versions = new Y2KTraderJoeZap.Version[](1);
        path.tokenPath = new IERC20[](2);

        path.pairBinSteps[0] = 15;
        path.versions[0] = Y2KTraderJoeZap.Version.V2_1;
        path.tokenPath[0] = IERC20(USDC_ADDRESS);
        path.tokenPath[1] = IERC20(WETH_ADDRESS);

        uint256 fromAmount = 100_000_000;
        uint256 toAmountMin = 500_000_000_000_000;
        uint256 id = EPOCH_ID;

        bool approved = IERC20(USDC_ADDRESS).approve(
            address(wrapperAddress),
            fromAmount
        );
        assertEq(approved, true);
        assertEq(
            IERC20(USDC_ADDRESS).allowance(sender, address(wrapperAddress)),
            fromAmount
        );
        assertEq(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 0);
        return (path, fromAmount, toAmountMin, id);
    }
}
