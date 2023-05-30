// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {Y2KCamelotZap} from "../src/zaps/Y2KCamelotZap.sol";
import {Y2KUniswapV2Zap} from "../src/zaps/Y2KUniswapV2Zap.sol";
import {Y2KChronosZap} from "../src/zaps/Y2KChronosZap.sol";
import {Y2KBalancerZap} from "../src/zaps/Y2KBalancerZap.sol";
import {Y2KUniswapV3Zap} from "../src/zaps/Y2KUniswapV3Zap.sol";
import {Y2KTraderJoeZap} from "../src/zaps/Y2KTraderJoeZap.sol";
import {Y2KCurveZap} from "../src/zaps/Y2KCurveZap.sol";
import {Y2KGMXZap} from "../src/zaps/Y2KGMXZap.sol";
import {IErrors} from "../src/interfaces/IErrors.sol";
import {ICamelotPair} from "../src/interfaces/ICamelotPair.sol";
import {IUniswapPair} from "../src/interfaces/IUniswapPair.sol";

import {IBalancerVault} from "../src/interfaces/IBalancerVault.sol";
import {IEarthQuakeVault, IERC1155} from "./Interfaces.sol";

interface IGMXVault {
    function getMinPrice(address) external view returns (uint256);

    function getMaxPrice(address) external view returns (uint256);
}

abstract contract Helper {
    address constant USDC_ADDRESS = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant USDT_ADDRESS = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant DAI_ADDRESS = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address constant WETH_ADDRESS = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant FRAX_ADDRESS = 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F;
    address constant DUSD_ADDRESS = 0xF0B5cEeFc89684889e5F7e0A7775Bd100FcD3709;
    address constant sender = address(0x01);
    uint256 constant BASIS_POINTS_DIVISOR = 10000;

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
    bytes32 constant DUSD_DAI_POOL_ID_BALANCER =
        0xd89746affa5483627a87e55713ec1905114394950002000000000000000000bf;
    address constant FRAX_USDC_POOL_CURVE =
        0xC9B8a3FDECB9D5b218d02555a8Baf332E5B740d5;
    address constant USDC_USDT_POOL_CURVE =
        0x7f90122BF0700F9E7e1F688fe926940E8839F353;
    address constant USDT_WETH_POOL_CURVE =
        0x960ea3e3C7FB317332d990873d354E18d7645590;
    address constant CAMELOT_USDC_WETH_PAIR =
        0x84652bb2539513BAf36e225c930Fdd8eaa63CE27;
    address constant SUSHI_USDC_WETH_PAIR =
        0x905dfCD5649217c42684f23958568e533C711Aa3;

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
        vm.label(USDT_ADDRESS, "USDT");
        vm.label(FRAX_ADDRESS, "FRAX");
        vm.label(GMX_VAULT, "GMX Vault");
        vm.label(BALANCER_VAULT, "Balancer Vault");
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

    /////////////////////////////////////////
    //               STATE VARS            //
    /////////////////////////////////////////

    function testStateVars_Camelotet() public {
        assertEq(zapCamelot.CAMELOT_V2_FACTORY(), CAMELOT_FACTORY);
        assertEq(zapCamelot.EARTHQUAKE_VAULT(), EARTHQUAKE_VAULT);
    }

    function testStateVars_Sushi() public {
        assertEq(zapSushiV2.UNISWAP_V2_FORK_FACTORY(), SUSHI_V2_FACTORY);
        assertEq(zapSushiV2.EARTHQUAKE_VAULT(), EARTHQUAKE_VAULT);
    }

    function testStateVars_Balancer() public {
        assertEq(address(zapBalancer.BALANCER_VAULT()), BALANCER_VAULT);
        assertEq(zapBalancer.EARTHQUAKE_VAULT(), EARTHQUAKE_VAULT);
    }

    function testStateVars_UniswapV3() public {
        assertEq(zapUniswapV3.UNISWAP_V3_FACTORY(), UNISWAP_V3_FACTORY);
        assertEq(zapUniswapV3.EARTHQUAKE_VAULT(), EARTHQUAKE_VAULT);
    }

    function testStateVars_Curve() public {
        assertEq(zapCurve.EARTHQUAKE_VAULT(), EARTHQUAKE_VAULT);
    }

    function testStateVars_GMX() public {
        assertEq(address(zapGMX.GMX_VAULT()), GMX_VAULT);
        assertEq(zapGMX.EARTHQUAKE_VAULT(), EARTHQUAKE_VAULT);
    }

    function testStateVars_TraderJoe() public {
        assertEq(address(zapTraderJoe.LEGACY_FACTORY()), TJ_LEGACY_FACTORY);
        assertEq(address(zapTraderJoe.FACTORY()), TJ_FACTORY);
        assertEq(address(zapTraderJoe.FACTORY_V1()), TJ_FACTORY_V1);
        assertEq(zapTraderJoe.EARTHQUAKE_VAULT(), EARTHQUAKE_VAULT);
    }

    function testStateVars_Chronos() public {
        assertEq(zapChronos.UNISWAP_V2_FORK_FACTORY(), CHRONOS_FACTORY);
        assertEq(zapChronos.EARTHQUAKE_VAULT(), EARTHQUAKE_VAULT);
    }

    /////////////////////////////////////////
    //                 ERRORS              //
    /////////////////////////////////////////

    function testErrors_Camelot() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KCamelotZap(address(0), EARTHQUAKE_VAULT);

        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KCamelotZap(CAMELOT_FACTORY, address(0));

        vm.startPrank(sender);
        (
            address[] memory path,
            uint256 fromAmount,
            ,
            uint256 id
        ) = setupUSDCtoWETHV2Fork(address(zapCamelot));

        // Dynamically fetch the amountOut
        uint256 amountOut = ICamelotPair(CAMELOT_USDC_WETH_PAIR).getAmountOut(
            fromAmount,
            path[0]
        );

        // Execute revert with dynamic data
        vm.expectRevert(
            abi.encodePacked(IErrors.InvalidMinOut.selector, amountOut)
        );
        zapCamelot.zapIn(path, fromAmount, amountOut + 1, id);
    }

    function testErrors_Sushi() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KUniswapV2Zap(address(0), EARTHQUAKE_VAULT);

        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KUniswapV2Zap(SUSHI_V2_FACTORY, address(0));

        vm.startPrank(sender);
        (
            address[] memory path,
            uint256 fromAmount,
            ,
            uint256 id
        ) = setupUSDCtoWETHV2Fork(address(zapSushiV2));

        // Dynamically fetch the amountOut
        (uint256 reserveA, uint256 reserveB, ) = IUniswapPair(
            SUSHI_USDC_WETH_PAIR
        ).getReserves();
        if (path[0] > path[1]) (reserveA, reserveB) = (reserveB, reserveA);
        uint256 amountOut = ((fromAmount * 997) * reserveB) /
            ((reserveA * 1000) + (fromAmount * 997));

        // Execute the revert with dynamic data
        vm.expectRevert(
            abi.encodePacked(IErrors.InvalidMinOut.selector, amountOut)
        );
        zapSushiV2.zapIn(path, fromAmount, amountOut + 1, id);
    }

    function testErors_UniswapV3() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KUniswapV3Zap(address(0), EARTHQUAKE_VAULT);

        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KUniswapV3Zap(UNISWAP_V3_FACTORY, address(0));

        // // staging for revert test
        // vm.startPrank(sender);
        // (
        //     address[] memory path,
        //     uint24[] memory fee,
        //     uint256 fromAmount,
        //     ,
        //     uint256 id
        // ) = setupUSDCtoWETHV3(address(zapUniswapV3));

        // // Dynamically fetch the amountOut
        // // TODO: Best way to fetch the dynamic value?
        // uint256 amountOut = 0;

        // // Execute the revert with dynamic data
        // vm.expectRevert(
        //     abi.encodePacked(IErrors.InvalidMinOut.selector, amountOut)
        // );
        // zapUniswapV3.zapIn(path, fee, fromAmount, toAmountMin, id);

        bytes memory data = abi.encode(USDC_ADDRESS, WETH_ADDRESS, 500);
        vm.expectRevert(IErrors.InvalidCaller.selector);
        zapUniswapV3.uniswapV3SwapCallback(100, 100, data);
    }

    function testErrors_Balancer() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KBalancerZap(address(0), EARTHQUAKE_VAULT);

        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KBalancerZap(BALANCER_VAULT, address(0));
    }

    function testErrors_Curve() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KCurveZap(address(0));

        // TODO: Invalid output from swap to wrong type of pool (zapInSingle)

        // staging for zapInSingles (Standard and ETH)
        vm.startPrank(sender);
        (
            address fromToken,
            ,
            int128 i,
            int128 j,
            address pool,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupUSDTtoWETHCurve(address(zapCurveUSDT), EARTHQUAKE_VAULT_USDT);

        vm.expectRevert(IErrors.InvalidOutput.selector);
        zapCurveUSDT.zapInSingleEth(
            fromToken,
            FRAX_ADDRESS,
            uint128(i),
            uint128(j),
            pool,
            fromAmount,
            toAmountMin,
            id
        );

        vm.expectRevert(IErrors.InvalidOutput.selector);
        zapCurveUSDT.zapInSingle(
            fromToken,
            FRAX_ADDRESS,
            i,
            j,
            pool,
            fromAmount,
            toAmountMin,
            id
        );

        (
            address[] memory path,
            address[] memory pools,
            uint256[] memory iValues,
            uint256[] memory jValues,
            ,
            ,

        ) = setupUSDCtoUSDTtoWETHCurve(
                address(zapCurveUSDT),
                EARTHQUAKE_VAULT_USDT
            );

        // changing amountOut to revert
        vm.expectRevert(IErrors.InvalidOutput.selector);
        zapCurveUSDT.zapInMulti(
            path,
            pools,
            iValues,
            jValues,
            fromAmount,
            100 ether,
            id
        );

        path[2] = FRAX_ADDRESS;
        vm.expectRevert(IErrors.InvalidOutput.selector);
        zapCurveUSDT.zapInMulti(
            path,
            pools,
            iValues,
            jValues,
            fromAmount,
            toAmountMin,
            id
        );

        // TODO: Invalid output from swap to wrong type of pool (zapInMulti)
    }

    function testErrors_GMX() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KGMXZap(address(0), EARTHQUAKE_VAULT);

        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KGMXZap(GMX_VAULT, address(0));

        // staging the revert test
        vm.startPrank(sender);
        (
            address[] memory path,
            uint256 fromAmount,
            ,
            uint256 id
        ) = setupUSDCtoWETHV2Fork(address(zapGMX)); // NOTE: Uses the same inputs as V2 forks

        // Dynamically fetch the amountOut
        uint256 priceIn = IGMXVault(GMX_VAULT).getMinPrice(path[0]);
        uint256 priceOut = IGMXVault(GMX_VAULT).getMaxPrice(path[1]);
        uint256 amountOut = (fromAmount * priceIn) / priceOut;
        amountOut = (amountOut * (10 ** 18)) / (10 ** 6);

        // amount after fees
        amountOut =
            (amountOut * (BASIS_POINTS_DIVISOR - 32)) /
            BASIS_POINTS_DIVISOR;

        vm.expectRevert(
            abi.encodePacked(IErrors.InvalidMinOut.selector, amountOut)
        );
        zapGMX.zapIn(path, fromAmount, amountOut + 1, id);
    }

    function testErrors_TraderJoe() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KTraderJoeZap(
            address(0),
            TJ_FACTORY,
            TJ_FACTORY_V1,
            EARTHQUAKE_VAULT
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KTraderJoeZap(
            TJ_LEGACY_FACTORY,
            address(0),
            TJ_FACTORY_V1,
            EARTHQUAKE_VAULT
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KTraderJoeZap(
            TJ_LEGACY_FACTORY,
            TJ_FACTORY,
            address(0),
            EARTHQUAKE_VAULT
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KTraderJoeZap(
            TJ_LEGACY_FACTORY,
            TJ_FACTORY,
            TJ_FACTORY_V1,
            address(0)
        );

        // TODO: InvalidMinOut from (zapIn)
        // TODO: InvalidPair from _getPair
        // TODO: InvalidPair from _getLBPairInformation
    }

    function testErrors_Chronos() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KChronosZap(address(0), EARTHQUAKE_VAULT);

        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KChronosZap(CHRONOS_FACTORY, address(0));
        // TODO: AmountOutMin insufficient
    }

    /////////////////////////////////////////
    //               HELPERS               //
    /////////////////////////////////////////

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

    function setupDAItoUSDCtoUSDTtoWETHV2Fork(
        address wrapperAddress
    ) public returns (address[] memory path, uint256, uint256, uint256) {
        uint256 fromAmount = 10e18;
        uint256 toAmountMin = 500_000_000_000_000;
        uint256 id = EPOCH_ID;

        deal(DAI_ADDRESS, sender, fromAmount);
        assertEq(IERC20(DAI_ADDRESS).balanceOf(sender), fromAmount);

        path = new address[](4);
        path[0] = DAI_ADDRESS;
        path[1] = USDC_ADDRESS;
        path[2] = USDT_ADDRESS;
        path[3] = WETH_ADDRESS;

        bool approved = IERC20(DAI_ADDRESS).approve(
            address(wrapperAddress),
            fromAmount
        );
        assertEq(approved, true);
        assertEq(
            IERC20(DAI_ADDRESS).allowance(sender, address(wrapperAddress)),
            fromAmount
        );
        assertEq(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 0);
        return (path, fromAmount, toAmountMin, id);
    }

    function setupWETHtoUSDCtoUSDTtoWETHV2Fork(
        address wrapperAddress
    ) public returns (address[] memory path, uint256, uint256, uint256) {
        uint256 fromAmount = 10e18;
        uint256 toAmountMin = 500_000_000_000_000;
        uint256 id = EPOCH_ID;

        deal(WETH_ADDRESS, sender, fromAmount);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(sender), fromAmount);

        path = new address[](4);
        path[0] = WETH_ADDRESS;
        path[1] = USDC_ADDRESS;
        path[2] = USDT_ADDRESS;
        path[3] = WETH_ADDRESS;

        bool approved = IERC20(WETH_ADDRESS).approve(
            address(wrapperAddress),
            fromAmount
        );
        assertEq(approved, true);
        assertEq(
            IERC20(WETH_ADDRESS).allowance(sender, address(wrapperAddress)),
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
        uint256 fromAmount = 10_000_000;
        uint256 toAmountMin = 500_000_000_000_000;
        id = 1684713600;

        deal(USDT_ADDRESS, sender, fromAmount);
        assertEq(IERC20(USDT_ADDRESS).balanceOf(sender), fromAmount);

        kind = IBalancerVault.SwapKind.GIVEN_IN;

        batchSwap = new IBalancerVault.BatchSwapStep[](2);
        batchSwap[0].poolId = USDT_USDC_POOL_ID_BALANCER;
        batchSwap[0].assetInIndex = 0;
        batchSwap[0].assetOutIndex = 1;
        batchSwap[0].amount = fromAmount;
        batchSwap[0].userData = bytes("");
        batchSwap[1].poolId = USDC_WETH_POOL_ID_BALANCER;
        batchSwap[1].assetInIndex = 1;
        batchSwap[1].assetOutIndex = 2;
        batchSwap[1].amount = 0;
        batchSwap[1].userData = bytes("");

        // Error likely linked to the index setup for assets
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

    function setupDUSDtoUSDTtoUSDCtoWETHBalancer(
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
        uint256 fromAmount = 10_000_000;
        uint256 toAmountMin = 500_000_000_000_000;
        id = 1684713600;

        deal(DUSD_ADDRESS, sender, fromAmount);
        assertEq(IERC20(DUSD_ADDRESS).balanceOf(sender), fromAmount);

        kind = IBalancerVault.SwapKind.GIVEN_IN;

        batchSwap = new IBalancerVault.BatchSwapStep[](3);
        batchSwap[0].poolId = DUSD_DAI_POOL_ID_BALANCER;
        batchSwap[0].assetInIndex = 0;
        batchSwap[0].assetOutIndex = 1;
        batchSwap[0].amount = fromAmount;
        batchSwap[0].userData = bytes("");
        batchSwap[1].poolId = USDT_USDC_POOL_ID_BALANCER; // Pool incl. USDT/USDC/DAI
        batchSwap[1].assetInIndex = 1;
        batchSwap[1].assetOutIndex = 2;
        batchSwap[1].amount = 0;
        batchSwap[1].userData = bytes("");
        batchSwap[2].poolId = USDC_WETH_POOL_ID_BALANCER;
        batchSwap[2].assetInIndex = 2;
        batchSwap[2].assetOutIndex = 3;
        batchSwap[2].amount = 0;
        batchSwap[2].userData = bytes("");

        // Error likely linked to the index setup for assets
        assets = new address[](4);
        assets[0] = DUSD_ADDRESS;
        assets[1] = DAI_ADDRESS;
        assets[2] = USDC_ADDRESS;
        assets[3] = WETH_ADDRESS;

        limits = new int256[](4);
        limits[0] = int256(fromAmount);
        limits[1] = 0;
        limits[2] = 0;
        limits[3] = int256(toAmountMin) - (2 * int256(toAmountMin));

        deadline = block.timestamp + 3600;

        bool approved = IERC20(DUSD_ADDRESS).approve(
            address(wrapperAddress),
            fromAmount
        );
        assertEq(approved, true);
        assertEq(
            IERC20(DUSD_ADDRESS).allowance(sender, address(wrapperAddress)),
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

    function setupDAItoUSDCtoUSDTtoWETHV3(
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
        uint256 fromAmount = 10e18;
        uint256 toAmountMin = 500_000_000_000_000;
        uint256 id = EPOCH_ID;

        deal(DAI_ADDRESS, sender, fromAmount);
        assertEq(IERC20(DAI_ADDRESS).balanceOf(sender), fromAmount);

        path = new address[](4);
        fee = new uint24[](3);

        path[0] = DAI_ADDRESS;
        path[1] = USDC_ADDRESS;
        path[2] = USDT_ADDRESS;
        path[3] = WETH_ADDRESS;
        fee[0] = 100;
        fee[1] = 100;
        fee[2] = 500;

        bool approved = IERC20(DAI_ADDRESS).approve(
            address(wrapperAddress),
            fromAmount
        );
        assertEq(approved, true);
        assertEq(
            IERC20(DAI_ADDRESS).allowance(sender, address(wrapperAddress)),
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
        pool = USDT_WETH_POOL_CURVE;

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
            address[] memory path,
            address[] memory pools,
            uint256[] memory i,
            uint256[] memory j,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        )
    {
        deal(USDC_ADDRESS, sender, 10_000_000);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 10e6);

        path = new address[](3);
        path[0] = USDC_ADDRESS;
        path[1] = USDT_ADDRESS;
        path[2] = WETH_ADDRESS;

        i = new uint256[](2);
        j = new uint256[](2);
        i[0] = 0;
        j[0] = 1;

        i[1] = 0;
        j[1] = 2;

        pools = new address[](2);
        pools[0] = USDC_USDT_POOL_CURVE;
        pools[1] = USDT_WETH_POOL_CURVE;

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

    function setupFRAXtoUSDCtoUSDTtoWETHCurve(
        address wrapperAddress,
        address vaultAddress
    )
        public
        returns (
            address[] memory path,
            address[] memory pools,
            uint256[] memory i,
            uint256[] memory j,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        )
    {
        fromAmount = 10e18;
        toAmountMin = 500_000_000_000_000;
        id = EPOCH_ID;

        deal(FRAX_ADDRESS, sender, fromAmount);
        assertEq(IERC20(FRAX_ADDRESS).balanceOf(sender), fromAmount);

        path = new address[](4);
        path[0] = FRAX_ADDRESS;
        path[1] = USDC_ADDRESS;
        path[2] = USDT_ADDRESS;
        path[3] = WETH_ADDRESS;

        i = new uint256[](3);
        j = new uint256[](3);

        i[0] = 0;
        j[0] = 1;

        i[1] = 0;
        j[1] = 1;

        i[2] = 0;
        j[2] = 2;

        pools = new address[](3);
        pools[0] = FRAX_USDC_POOL_CURVE;
        pools[1] = USDC_USDT_POOL_CURVE;
        pools[2] = USDT_WETH_POOL_CURVE;

        bool approved = IERC20(FRAX_ADDRESS).approve(
            address(wrapperAddress),
            fromAmount
        );
        assertEq(approved, true);
        assertEq(
            IERC20(FRAX_ADDRESS).allowance(sender, address(wrapperAddress)),
            fromAmount
        );
        assertEq(IERC1155(vaultAddress).balanceOf(sender, id), 0);
    }

    // TODO: Curve 3x swap

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
