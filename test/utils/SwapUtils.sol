// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "forge-std/Test.sol";
import {PermitUtils} from "./PermitUtils.sol";
import {Helper} from "./Helper.sol";

import {Y2KCamelotZap} from "../../src//zaps/Y2KCamelotZap.sol";
import {Y2KUniswapV2Zap} from "../../src//zaps/Y2KUniswapV2Zap.sol";
import {Y2KChronosZap} from "../../src//zaps/Y2KChronosZap.sol";
import {Y2KBalancerZap} from "../../src//zaps/Y2KBalancerZap.sol";
import {Y2KUniswapV3Zap} from "../../src//zaps/Y2KUniswapV3Zap.sol";
import {Y2KTraderJoeZap} from "../../src//zaps/Y2KTraderJoeZap.sol";
import {Y2KCurveZap} from "../../src//zaps/Y2KCurveZap.sol";
import {Y2KGMXZap} from "../../src//zaps/Y2KGMXZap.sol";

import {IBalancerVault} from "../../src/interfaces/dexes/IBalancerVault.sol";
import {IEarthQuakeVault, IERC1155} from "./Interfaces.sol";
import {ICamelotPair} from "../../src/interfaces/dexes/ICamelotPair.sol";
import {IUniswapPair} from "../../src/interfaces/dexes/IUniswapPair.sol";
import {ISignatureTransfer} from "../../src/interfaces/ISignatureTransfer.sol";
import {IPermit2} from "./Interfaces.sol";

interface IGMXVault {
    function getMinPrice(address) external view returns (uint256);

    function getMaxPrice(address) external view returns (uint256);
}

contract SwapHelper is Helper, PermitUtils {
    Y2KCamelotZap public zapCamelot;
    Y2KUniswapV2Zap public zapSushiV2;
    Y2KChronosZap public zapChronos;
    Y2KBalancerZap public zapBalancer;
    Y2KUniswapV3Zap public zapUniswapV3;
    Y2KCurveZap public zapCurve;
    Y2KCurveZap public zapCurveUSDT;
    Y2KGMXZap public zapGMX;
    Y2KTraderJoeZap public zapTraderJoe;
    IPermit2 public permit2;

    address constant depositReceiver = address(0x11);

    uint256 mainnetFork;
    uint256 arbitrumFork;

    function setUp() public virtual {
        mainnetFork = vm.createSelectFork(MAINNET_RPC_URL, 17269532);
        arbitrumFork = vm.createFork(ARBITRUM_RPC_URL);
        vm.selectFork(arbitrumFork);
        vm.warp(EPOCH_BEGIN - 1);
        // vm.roll(90815015);

        zapCamelot = new Y2KCamelotZap(CAMELOT_FACTORY, PERMIT_2);
        zapSushiV2 = new Y2KUniswapV2Zap(SUSHI_V2_FACTORY, PERMIT_2);
        zapBalancer = new Y2KBalancerZap(BALANCER_VAULT, PERMIT_2);
        zapUniswapV3 = new Y2KUniswapV3Zap(UNISWAP_V3_FACTORY, PERMIT_2);
        zapCurve = new Y2KCurveZap(WETH_ADDRESS, PERMIT_2);
        zapCurveUSDT = new Y2KCurveZap(WETH_ADDRESS, PERMIT_2);
        zapGMX = new Y2KGMXZap(GMX_VAULT, PERMIT_2);

        zapTraderJoe = new Y2KTraderJoeZap(
            TJ_LEGACY_FACTORY,
            TJ_FACTORY,
            TJ_FACTORY_V1
        );
        zapChronos = new Y2KChronosZap(CHRONOS_FACTORY);

        vm.label(sender, "Sender");
        vm.label(depositReceiver, "Receiver");
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

        permit2 = IPermit2(PERMIT_2);
        permitSender = vm.addr(permitSenderKey);
        permitReceiver = vm.addr(permitReceiverKey);
        vm.label(permitSender, "PermitSender");
        vm.label(permitReceiver, "PermitReceiver");

        setERC20TestTokenApprovals(vm, permitSender, PERMIT_2);
    }

    function setERC20TestTokenApprovals(
        Vm vm,
        address owner,
        address spender
    ) public {
        vm.startPrank(owner);
        IERC20(USDC_ADDRESS).approve(spender, type(uint256).max);
        IERC20(USDT_ADDRESS).approve(spender, type(uint256).max);
        IERC20(WETH_ADDRESS).approve(spender, type(uint256).max);
        vm.stopPrank();
    }

    /////////////////////////////////////////
    //        SIMPLE SWAP HELPERS           //
    /////////////////////////////////////////

    function setupUSDCtoWETHV2Fork(
        address wrapperAddress,
        address senderAddress
    ) public returns (address[] memory path, uint256, uint256, uint256) {
        deal(USDC_ADDRESS, senderAddress, 10_000_000);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(senderAddress), 10e6);

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
            IERC20(USDC_ADDRESS).allowance(
                senderAddress,
                address(wrapperAddress)
            ),
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
        address wrapperAddress,
        address senderAddress
    )
        public
        returns (
            IBalancerVault.SingleSwap memory singleSwap,
            uint256,
            uint256,
            uint256
        )
    {
        deal(USDC_ADDRESS, senderAddress, 10_000_000);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(senderAddress), 10e6);

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
            IERC20(USDC_ADDRESS).allowance(
                senderAddress,
                address(wrapperAddress)
            ),
            fromAmount
        );
        assertEq(IERC1155(EARTHQUAKE_VAULT).balanceOf(senderAddress, id), 0);

        return (singleSwap, fromAmount, toAmountMin, id);
    }

    function setupUSDTtoUSDCtoWETHBalancer(
        address wrapperAddress,
        address senderAddress
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

        deal(USDT_ADDRESS, senderAddress, fromAmount);
        assertEq(IERC20(USDT_ADDRESS).balanceOf(senderAddress), fromAmount);

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
            IERC20(USDT_ADDRESS).allowance(
                senderAddress,
                address(wrapperAddress)
            ),
            fromAmount
        );
        assertEq(IERC1155(EARTHQUAKE_VAULT).balanceOf(senderAddress, id), 0);

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
        uint256 toAmountMin = 50_000_000_000_000;
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
        address wrapperAddress,
        address senderAddress
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
        deal(USDC_ADDRESS, senderAddress, 10_000_000);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(senderAddress), 10e6);

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
            IERC20(USDC_ADDRESS).allowance(
                senderAddress,
                address(wrapperAddress)
            ),
            fromAmount
        );
        assertEq(IERC1155(EARTHQUAKE_VAULT).balanceOf(senderAddress, id), 0);
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
        address vaultAddress,
        address senderAddress
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
        deal(USDT_ADDRESS, senderAddress, 10_000_000);
        assertEq(IERC20(USDT_ADDRESS).balanceOf(senderAddress), 10e6);

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
            IERC20(USDT_ADDRESS).allowance(
                senderAddress,
                address(wrapperAddress)
            ),
            fromAmount
        );
        assertEq(IERC1155(vaultAddress).balanceOf(senderAddress, id), 0);
    }

    function setupUSDCtoUSDTtoWETHCurve(
        address wrapperAddress,
        address vaultAddress,
        address senderAddress
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
        deal(USDC_ADDRESS, senderAddress, 10_000_000);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(senderAddress), 10e6);

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
            IERC20(USDC_ADDRESS).allowance(
                senderAddress,
                address(wrapperAddress)
            ),
            fromAmount
        );
        assertEq(IERC1155(vaultAddress).balanceOf(senderAddress, id), 0);
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

    /////////////////////////////////////////
    //        PERMIT SWAP HELPERS           //
    /////////////////////////////////////////
    function setupPermitSwap(
        address receiver,
        address spender,
        uint256 fromAmount,
        address token
    )
        public
        view
        returns (
            ISignatureTransfer.PermitTransferFrom memory permit,
            ISignatureTransfer.SignatureTransferDetails memory transferDetails,
            bytes memory sig
        )
    {
        uint256 nonce = 0;
        permit = defaultERC20PermitTransfer(token, nonce, fromAmount);
        transferDetails = getTransferDetails(receiver, fromAmount);
        bytes32 domainSeparator = permit2.DOMAIN_SEPARATOR();
        sig = getPermitTransferSignature(
            permit,
            permitSenderKey,
            spender,
            domainSeparator
        );
    }
}
