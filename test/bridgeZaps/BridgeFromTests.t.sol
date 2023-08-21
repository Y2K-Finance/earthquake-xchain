// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "forge-std/Test.sol";
import {BridgeHelper} from "../utils/BridgeUtils.sol";
import {ZapFrom} from "../../src/bridgeZaps/zapFrom.sol";
import {IErrors} from "../../src/interfaces/IErrors.sol";
import {BytesLib} from "../../src/libraries/BytesLib.sol";
import {IEarthQuakeVault, IERC1155, IEarthquakeController, IStargateRouter, IBalancer} from "../utils/Interfaces.sol";
import {ISignatureTransfer} from "../../src/interfaces/ISignatureTransfer.sol";
import {IPermit2 as Permit2} from "../../src/interfaces/IPermit2.sol";

import "forge-std/console.sol";

contract BridgeFromTests is BridgeHelper {
    uint16 public ethRouterPoolId = 13;
    address public constant stargateFactory =
        0x06D538690AF257Da524f25D0CD52fD85b1c2173E;

    /////////////////////////////////////////
    //               CONFIG                //
    /////////////////////////////////////////
    function setUp() public {
        setUpMainnet();
    }

    function test_forkFrom() public {
        assertEq(vm.activeFork(), mainnetFork);
        uint256 supply = IERC20(USDC_ADDRESS_ETH).totalSupply();
        assertTrue(supply != 0);

        assertEq(IStargateRouter(STARGATE_ROUTER).factory(), stargateFactory);
        assertEq(
            IStargateRouter(STARGATE_ROUTER_USINGETH).poolId(),
            ethRouterPoolId
        );
    }

    /////////////////////////////////////////
    //               STATE VARS            //
    /////////////////////////////////////////
    function test_stateVarsFrom() public {
        assertEq(address(zapFrom.permit2()), PERMIT_2);
        assertEq(zapFrom.stargateRouter(), STARGATE_ROUTER);
        assertEq(zapFrom.stargateRouterEth(), STARGATE_ROUTER_USINGETH);
        assertEq(zapFrom.layerZeroRouter(), LAYER_ZERO_ROUTER_LOCAL);
        assertEq(zapFrom.y2kArbRouter(), y2kArbRouter);
        assertEq(
            zapFrom.layerZeroRemoteAndLocal(),
            abi.encodePacked(y2kArbRouter, address(zapFrom))
        );
        assertEq(zapFrom.uniswapV2ForkFactory(), UNISWAP_V2_FACTORY);
        assertEq(zapFrom.sushiFactory(), SUSHI_V2_FACTORY_ETH);
        assertEq(zapFrom.uniswapV3Factory(), UNISWAP_V3_FACTORY);
        assertEq(zapFrom.balancerVault(), BALANCER_VAULT);
        assertEq(zapFrom.wethAddress(), WETH_ADDRESS_ETH);
    }

    /////////////////////////////////////////
    //         BRIDGE FUNCTIONS            //
    /////////////////////////////////////////
    function test_bridgeETH() public {
        uint256 amountIn = 1.01 ether;
        uint256 amount = 1 ether;
        address fromToken = address(0);
        uint16 srcPoolId = 13; // What should this be?
        uint16 dstPoolId = 13; // What should this be?
        bytes memory payload = abi.encode(sender, EPOCH_ID, EARTHQUAKE_VAULT);
        uint256 balance = sender.balance;

        vm.startPrank(sender);
        zapFrom.bridge{value: amountIn}(
            amount,
            fromToken,
            srcPoolId,
            dstPoolId,
            payload
        );

        assertLe(sender.balance, balance);
        vm.stopPrank();
    }

    function test_bridgeERC20() public {
        uint256 amountIn = 1000e6;
        address fromToken = USDC_ADDRESS_ETH;
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 1;
        bytes memory payload = abi.encode(sender, EPOCH_ID, EARTHQUAKE_VAULT);

        vm.startPrank(sender);
        deal(USDC_ADDRESS_ETH, sender, amountIn);
        assertEq(IERC20(USDC_ADDRESS_ETH).balanceOf(sender), amountIn);

        // TODO: Best way to estimate the msg.value?
        // TODO: Knowing what msg.value should be to avoid LZ error - LayerZero: not enough native for fees
        IERC20(USDC_ADDRESS_ETH).approve(address(zapFrom), amountIn);
        zapFrom.bridge{value: 0.1 ether}(
            amountIn,
            fromToken,
            srcPoolId,
            dstPoolId,
            payload
        );

        assertEq(IERC20(USDC_ADDRESS_ETH).balanceOf(sender), 0);
        vm.stopPrank();
    }

    function test_withdrawFrom() public {
        address receiver = refundSender;
        bytes1 funcSelector = 0x01;
        bytes1 bridgeId = 0x02;
        address vaultAddress = SGETH_ADDRESS;
        bytes memory payload = abi.encode(
            funcSelector,
            bridgeId,
            receiver,
            EPOCH_ID,
            vaultAddress
        );

        vm.startPrank(sender);
        zapFrom.withdraw{value: 0.1 ether}(payload);
        vm.stopPrank();
    }

    /////////////////////////////////////////
    //     BRIDGE & SWAP FUNCTIONS ERC20    //
    /////////////////////////////////////////
    function test_swapUniV2bridge() public {
        uint256 amountIn = 1e18;
        address fromToken = WETH_ADDRESS_ETH;
        address receivedToken = USDC_ADDRESS_ETH;
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 1;

        bytes1 dexId = 0x01;
        address[] memory path = new address[](2);
        path[0] = fromToken;
        path[1] = receivedToken;
        uint256 toAmountMin = 1000e6;
        bytes memory swapPayload = abi.encode(path, toAmountMin);
        bytes memory bridgePayload = abi.encode(
            sender,
            EPOCH_ID,
            EARTHQUAKE_VAULT
        );

        vm.startPrank(sender);
        deal(WETH_ADDRESS_ETH, sender, amountIn);
        assertEq(IERC20(WETH_ADDRESS_ETH).balanceOf(sender), amountIn);

        IERC20(WETH_ADDRESS_ETH).approve(address(zapFrom), amountIn);
        zapFrom.swapAndBridge{value: 0.1 ether}(
            amountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
            dexId,
            swapPayload,
            bridgePayload
        );

        assertEq(IERC20(WETH_ADDRESS_ETH).balanceOf(sender), 0);
        vm.stopPrank();
    }

    function test_swapSushibridge() public {
        uint256 amountIn = 1e18;
        address fromToken = WETH_ADDRESS_ETH;
        address receivedToken = USDC_ADDRESS_ETH;
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 1;

        bytes1 dexId = 0x03;
        address[] memory path = new address[](2);
        path[0] = fromToken;
        path[1] = receivedToken;
        uint256 toAmountMin = 1000e6;
        bytes memory swapPayload = abi.encode(path, toAmountMin);
        bytes memory bridgePayload = abi.encode(
            sender,
            EPOCH_ID,
            EARTHQUAKE_VAULT
        );

        vm.startPrank(sender);
        deal(WETH_ADDRESS_ETH, sender, amountIn);
        assertEq(IERC20(WETH_ADDRESS_ETH).balanceOf(sender), amountIn);

        IERC20(WETH_ADDRESS_ETH).approve(address(zapFrom), amountIn);
        zapFrom.swapAndBridge{value: 0.1 ether}(
            amountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
            dexId,
            swapPayload,
            bridgePayload
        );

        assertEq(IERC20(WETH_ADDRESS_ETH).balanceOf(sender), 0);
        vm.stopPrank();
    }

    function test_swapUniV3bridge() public {
        uint256 amountIn = 1e18;
        address fromToken = WETH_ADDRESS_ETH;
        address receivedToken = USDC_ADDRESS_ETH;
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 1;

        bytes1 dexId = 0x02;
        address[] memory path = new address[](2);
        path[0] = fromToken;
        path[1] = receivedToken;
        uint24[] memory fee = new uint24[](1);
        fee[0] = 500;
        uint256 toAmountMin = 1000e6;
        bytes memory swapPayload = abi.encode(path, fee, toAmountMin);
        bytes memory bridgePayload = abi.encode(
            sender,
            EPOCH_ID,
            EARTHQUAKE_VAULT
        );

        vm.startPrank(sender);
        deal(WETH_ADDRESS_ETH, sender, amountIn);
        assertEq(IERC20(WETH_ADDRESS_ETH).balanceOf(sender), amountIn);

        IERC20(WETH_ADDRESS_ETH).approve(address(zapFrom), amountIn);
        zapFrom.swapAndBridge{value: 0.1 ether}(
            amountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
            dexId,
            swapPayload,
            bridgePayload
        );

        assertEq(IERC20(WETH_ADDRESS_ETH).balanceOf(sender), 0);
        vm.stopPrank();
    }

    function test_swapCurve() public {
        uint256 amountIn = 1000e18;
        address fromToken = DAI_ADDRESS_ETH;
        address receivedToken = USDC_ADDRESS_ETH;
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 1;
        int128 i = 0;
        int128 j = 1;
        address pool = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
        uint256 toAmountMin = 900e6;

        bytes memory swapPayload = abi.encode(
            bytes1(0x01), // swapType 1 on Curve
            fromToken,
            receivedToken,
            i,
            j,
            pool,
            amountIn,
            toAmountMin
        );
        bytes memory bridgePayload = abi.encode(
            sender,
            EPOCH_ID,
            EARTHQUAKE_VAULT
        );

        vm.startPrank(sender);
        deal(DAI_ADDRESS_ETH, sender, amountIn);
        assertEq(IERC20(DAI_ADDRESS_ETH).balanceOf(sender), amountIn);

        IERC20(DAI_ADDRESS_ETH).approve(address(zapFrom), amountIn);
        zapFrom.swapAndBridge{value: 0.1 ether}(
            amountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
            0x04, // Curve dexId
            swapPayload,
            bridgePayload
        );

        assertEq(IERC20(DAI_ADDRESS_ETH).balanceOf(sender), 0);
        vm.stopPrank();
    }

    function _setupCurveMultiBridge(
        uint256 amountIn,
        address fromToken,
        address receivedToken
    ) internal pure returns (bytes memory, bytes memory) {
        uint256 toAmountMin = 1e16;

        address[] memory path = new address[](3);
        path[0] = fromToken;
        path[1] = USDT_ADDRESS_ETH;
        path[2] = receivedToken;

        address[] memory pools = new address[](2);
        pools[0] = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
        pools[1] = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;

        uint256[] memory iValues = new uint256[](2);
        uint256[] memory jValues = new uint256[](2);
        iValues[0] = 1;
        jValues[0] = 2;
        iValues[1] = 0;
        jValues[1] = 2;
        return (
            abi.encode(
                bytes1(0x03), // swapType 3 on Curve
                path,
                pools,
                iValues,
                jValues,
                amountIn,
                toAmountMin
            ),
            abi.encode(sender, EPOCH_ID, EARTHQUAKE_VAULT)
        );
    }

    // TODO: Swapping ETH and need this to swap to ERC20
    function test_swapCurveMulti() public {
        uint256 amountIn = 100e6;
        address fromToken = USDC_ADDRESS_ETH;
        address receivedToken = address(0);
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 1;
        (
            bytes memory swapPayload,
            bytes memory bridgePayload
        ) = _setupCurveMultiBridge(amountIn, fromToken, receivedToken);
        vm.startPrank(sender);
        deal(USDC_ADDRESS_ETH, sender, amountIn);
        assertEq(IERC20(USDC_ADDRESS_ETH).balanceOf(sender), amountIn);

        IERC20(USDC_ADDRESS_ETH).approve(address(zapFrom), amountIn);
        zapFrom.swapAndBridge{value: 0.1 ether}(
            amountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
            0x04, // Curve dexId
            swapPayload,
            bridgePayload
        );

        assertEq(IERC20(USDC_ADDRESS_ETH).balanceOf(sender), 0);
        vm.stopPrank();
    }

    function test_swapBalancerbridge() public {
        uint256 amountIn = 100e18;
        uint256 toAmountMin = 90e6;
        bytes32 poolId = 0x79c58f70905f734641735bc61e45c19dd9ad60bc0000000000000000000004e7;
        address fromToken = DAI_ADDRESS_ETH;
        address receivedToken = USDC_ADDRESS_ETH;
        uint256 deadline = block.timestamp + 1000;

        uint16 srcPoolId = 1;
        uint16 dstPoolId = 1;

        IBalancer.SingleSwap memory singleSwap = IBalancer.SingleSwap({
            poolId: poolId,
            kind: IBalancer.SwapKind.GIVEN_IN,
            assetIn: fromToken,
            assetOut: receivedToken,
            amount: amountIn,
            userData: ""
        });
        IBalancer.Funds memory funds = IBalancer.Funds({
            sender: payable(address(zapFrom)),
            fromInternalBalance: false,
            recipient: payable(address(zapFrom)),
            toInternalBalance: false
        });
        bytes memory swapPayload = abi.encodeWithSelector(
            IBalancer.swap.selector,
            singleSwap,
            funds,
            toAmountMin,
            deadline
        );
        bytes memory bridgePayload = abi.encode(
            sender,
            EPOCH_ID,
            EARTHQUAKE_VAULT
        );

        vm.startPrank(sender);
        deal(DAI_ADDRESS_ETH, sender, amountIn);
        assertEq(IERC20(DAI_ADDRESS_ETH).balanceOf(sender), amountIn);

        IERC20(DAI_ADDRESS_ETH).approve(address(zapFrom), amountIn);
        zapFrom.swapAndBridge{value: 0.1 ether}(
            amountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
            0x05, // Balancer dexId
            swapPayload,
            bridgePayload
        );

        assertEq(IERC20(DAI_ADDRESS_ETH).balanceOf(sender), 0);
        vm.stopPrank();
    }

    function _setupBalancerMultiBridge(
        bytes32 firstPoolId,
        bytes32 secondPoolId,
        uint256 amountIn,
        uint256 toAmountMin,
        address fromToken,
        address connectorToken,
        address receivedToken,
        uint256 deadline,
        uint256[] memory assetIndexes
    ) internal view returns (bytes memory swapPayload) {
        IBalancer.SwapKind kind = IBalancer.SwapKind.GIVEN_IN;
        IBalancer.BatchSwapStep[] memory swaps = new IBalancer.BatchSwapStep[](
            2
        );
        swaps[0] = IBalancer.BatchSwapStep({
            poolId: firstPoolId,
            assetInIndex: assetIndexes[0],
            assetOutIndex: assetIndexes[1],
            amount: amountIn,
            userData: ""
        });
        swaps[1] = IBalancer.BatchSwapStep({
            poolId: secondPoolId,
            assetInIndex: assetIndexes[1],
            assetOutIndex: assetIndexes[2],
            amount: 0,
            userData: ""
        });

        address[] memory assets = new address[](3);
        assets[0] = fromToken;
        assets[1] = connectorToken;
        assets[2] = receivedToken;

        IBalancer.Funds memory funds = IBalancer.Funds({
            sender: payable(address(zapFrom)),
            fromInternalBalance: false,
            recipient: payable(address(zapFrom)),
            toInternalBalance: false
        });

        int256[] memory limits = new int256[](3);
        limits[0] = int256(amountIn);
        limits[1] = int256(0);
        limits[2] = -int256(toAmountMin);

        return
            abi.encodeWithSelector(
                IBalancer.batchSwap.selector,
                kind,
                swaps,
                assets,
                funds,
                limits,
                deadline
            );
    }

    function test_swapMultiBalancerbridge() public {
        uint256 amountIn = 1e17;
        uint256 toAmountMin = 100e6;
        bytes32 firstPoolId = 0x0b09dea16768f0799065c475be02919503cb2a3500020000000000000000001a;
        bytes32 secondPoolId = 0x79c58f70905f734641735bc61e45c19dd9ad60bc0000000000000000000004e7;
        address fromToken = WETH_ADDRESS_ETH;
        address connectorToken = DAI_ADDRESS_ETH;
        address receivedToken = USDC_ADDRESS_ETH;

        // NOTE: Indexes for each swap e.g. [0] is assetIn and [1] is assetOut etc.
        uint256[] memory assetIndexes = new uint256[](3);
        assetIndexes[0] = 0;
        assetIndexes[1] = 1;
        assetIndexes[2] = 2;

        uint16 srcPoolId = 1;
        uint16 dstPoolId = 1;

        bytes memory swapPayload = _setupBalancerMultiBridge(
            firstPoolId,
            secondPoolId,
            amountIn,
            toAmountMin,
            fromToken,
            connectorToken,
            receivedToken,
            block.timestamp + 1000,
            assetIndexes
        );
        bytes memory bridgePayload = abi.encode(
            sender,
            EPOCH_ID,
            EARTHQUAKE_VAULT
        );

        vm.startPrank(sender);
        deal(WETH_ADDRESS_ETH, sender, amountIn);
        assertEq(IERC20(WETH_ADDRESS_ETH).balanceOf(sender), amountIn);

        IERC20(WETH_ADDRESS_ETH).approve(address(zapFrom), amountIn);
        zapFrom.swapAndBridge{value: 0.2 ether}(
            amountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
            0x05, // Balancer dexId
            swapPayload,
            bridgePayload
        );

        assertEq(IERC20(WETH_ADDRESS_ETH).balanceOf(sender), 0);
        vm.stopPrank();
    }

    /////////////////////////////////////////
    // BRIDGE & PERMIT2 SWAP FUNCTIONS ERC20//
    /////////////////////////////////////////
    function test_PermitTransferFrom() private {
        vm.startPrank(permitSender);
        uint256 fromAmount = 10e6;

        deal(USDC_ADDRESS_ETH, permitSender, fromAmount);
        assertEq(IERC20(USDC_ADDRESS_ETH).balanceOf(permitSender), fromAmount);

        (
            ISignatureTransfer.PermitTransferFrom memory permit,
            ISignatureTransfer.SignatureTransferDetails memory transferDetails,
            bytes memory sig
        ) = setupPermitSwap(
                permitReceiver,
                permitReceiver,
                fromAmount,
                USDC_ADDRESS_ETH
            );
        vm.startPrank(permitReceiver);
        Permit2(PERMIT_2).permitTransferFrom(
            permit,
            transferDetails,
            permitSender,
            sig
        );

        assertEq(IERC20(USDC_ADDRESS_ETH).balanceOf(permitSender), 0);
        assertEq(
            IERC20(USDC_ADDRESS_ETH).balanceOf(permitReceiver),
            fromAmount
        );
        vm.stopPrank();
    }

    function test_permitSwapUniV2bridge() private {
        uint256 amountIn = 1e18;
        address fromToken = WETH_ADDRESS_ETH;
        address receivedToken = USDC_ADDRESS_ETH;
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 1;

        bytes1 dexId = 0x01;
        address[] memory path = new address[](2);
        path[0] = fromToken;
        path[1] = receivedToken;
        uint256 toAmountMin = 1000e6;
        bytes memory swapPayload = abi.encode(path, toAmountMin);
        bytes memory bridgePayload = abi.encode(
            permitSender,
            EPOCH_ID,
            EARTHQUAKE_VAULT
        );

        vm.deal(permitSender, 1e18);
        deal(fromToken, permitSender, amountIn);
        assertEq(IERC20(fromToken).balanceOf(permitSender), amountIn);

        vm.startPrank(permitSender);
        (
            ISignatureTransfer.PermitTransferFrom memory permit,
            ISignatureTransfer.SignatureTransferDetails memory transferDetails,
            bytes memory sig
        ) = setupPermitSwap(
                address(zapFrom),
                address(zapFrom),
                amountIn,
                fromToken
            );

        zapFrom.permitSwapAndBridge{value: 0.1 ether}(
            receivedToken,
            srcPoolId,
            dstPoolId,
            dexId,
            permit,
            transferDetails,
            sig,
            swapPayload,
            bridgePayload
        );

        assertEq(IERC20(fromToken).balanceOf(permitSender), 0);
        vm.stopPrank();
    }

    function test_permitSwapSushibridge() private {
        uint256 amountIn = 1e18;
        address fromToken = WETH_ADDRESS_ETH;
        address receivedToken = USDC_ADDRESS_ETH;
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 1;

        bytes1 dexId = 0x03;
        address[] memory path = new address[](2);
        path[0] = fromToken;
        path[1] = receivedToken;
        uint256 toAmountMin = 1000e6;
        bytes memory swapPayload = abi.encode(path, toAmountMin);
        bytes memory bridgePayload = abi.encode(
            sender,
            EPOCH_ID,
            EARTHQUAKE_VAULT
        );

        vm.startPrank(sender);
        deal(WETH_ADDRESS_ETH, sender, amountIn);
        assertEq(IERC20(WETH_ADDRESS_ETH).balanceOf(sender), amountIn);

        IERC20(WETH_ADDRESS_ETH).approve(address(zapFrom), amountIn);
        zapFrom.swapAndBridge{value: 0.1 ether}(
            amountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
            dexId,
            swapPayload,
            bridgePayload
        );

        assertEq(IERC20(WETH_ADDRESS_ETH).balanceOf(sender), 0);
        vm.stopPrank();
    }

    function test_permitSwapUniV3bridge() private {
        uint256 amountIn = 1e18;
        address fromToken = WETH_ADDRESS_ETH;
        address receivedToken = USDC_ADDRESS_ETH;
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 1;

        bytes1 dexId = 0x02;
        address[] memory path = new address[](2);
        path[0] = fromToken;
        path[1] = receivedToken;
        uint24[] memory fee = new uint24[](1);
        fee[0] = 500;
        uint256 toAmountMin = 1000e6;
        bytes memory swapPayload = abi.encode(path, fee, toAmountMin);
        bytes memory bridgePayload = abi.encode(
            sender,
            EPOCH_ID,
            EARTHQUAKE_VAULT
        );

        vm.startPrank(sender);
        deal(WETH_ADDRESS_ETH, sender, amountIn);
        assertEq(IERC20(WETH_ADDRESS_ETH).balanceOf(sender), amountIn);

        IERC20(WETH_ADDRESS_ETH).approve(address(zapFrom), amountIn);
        zapFrom.swapAndBridge{value: 0.1 ether}(
            amountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
            dexId,
            swapPayload,
            bridgePayload
        );

        assertEq(IERC20(WETH_ADDRESS_ETH).balanceOf(sender), 0);
        vm.stopPrank();
    }

    /////////////////////////////////////////
    //       BRIDGE & SWAP FUNCTIONS ETH    //
    /////////////////////////////////////////
    function test_swapEthUniV2bridge() public {
        uint256 amountIn = 100e6;
        address fromToken = USDC_ADDRESS_ETH;
        address receivedToken = WETH_ADDRESS_ETH;
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 1;

        bytes1 dexId = 0x01;
        address[] memory path = new address[](2);
        path[0] = fromToken;
        path[1] = receivedToken;
        uint256 toAmountMin = 1e16;
        bytes memory swapPayload = abi.encode(path, toAmountMin);
        bytes memory bridgePayload = abi.encode(
            sender,
            EPOCH_ID,
            EARTHQUAKE_VAULT
        );

        vm.startPrank(sender);
        deal(USDC_ADDRESS_ETH, sender, amountIn);
        assertEq(IERC20(USDC_ADDRESS_ETH).balanceOf(sender), amountIn);

        IERC20(USDC_ADDRESS_ETH).approve(address(zapFrom), amountIn);
        zapFrom.swapAndBridge{value: 0.1 ether}(
            amountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
            dexId,
            swapPayload,
            bridgePayload
        );

        assertEq(IERC20(USDC_ADDRESS_ETH).balanceOf(sender), 0);
        vm.stopPrank();
    }

    function test_swapEthSushibridge() public {
        uint256 amountIn = 100e6;
        address fromToken = USDC_ADDRESS_ETH;
        address receivedToken = WETH_ADDRESS_ETH;
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 1;

        bytes1 dexId = 0x03;
        address[] memory path = new address[](2);
        path[0] = fromToken;
        path[1] = receivedToken;
        uint256 toAmountMin = 1e16;
        bytes memory swapPayload = abi.encode(path, toAmountMin);
        bytes memory bridgePayload = abi.encode(
            sender,
            EPOCH_ID,
            EARTHQUAKE_VAULT
        );

        vm.startPrank(sender);
        deal(USDC_ADDRESS_ETH, sender, amountIn);
        assertEq(IERC20(USDC_ADDRESS_ETH).balanceOf(sender), amountIn);

        IERC20(USDC_ADDRESS_ETH).approve(address(zapFrom), amountIn);
        zapFrom.swapAndBridge{value: 0.1 ether}(
            amountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
            dexId,
            swapPayload,
            bridgePayload
        );

        assertEq(IERC20(USDC_ADDRESS_ETH).balanceOf(sender), 0);
        vm.stopPrank();
    }

    function test_swapEthUniV3bridge() public {
        uint256 amountIn = 100e6;
        address fromToken = USDC_ADDRESS_ETH;
        address receivedToken = WETH_ADDRESS_ETH;
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 1;

        bytes1 dexId = 0x02;
        address[] memory path = new address[](2);
        path[0] = fromToken;
        path[1] = receivedToken;
        uint24[] memory fee = new uint24[](1);
        fee[0] = 500;
        uint256 toAmountMin = 1e16;
        bytes memory swapPayload = abi.encode(path, fee, toAmountMin);
        bytes memory bridgePayload = abi.encode(
            sender,
            EPOCH_ID,
            EARTHQUAKE_VAULT
        );

        vm.startPrank(sender);
        deal(USDC_ADDRESS_ETH, sender, amountIn);
        assertEq(IERC20(USDC_ADDRESS_ETH).balanceOf(sender), amountIn);

        IERC20(USDC_ADDRESS_ETH).approve(address(zapFrom), amountIn);
        zapFrom.swapAndBridge{value: 0.1 ether}(
            amountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
            dexId,
            swapPayload,
            bridgePayload
        );

        assertEq(IERC20(USDC_ADDRESS_ETH).balanceOf(sender), 0);
        vm.stopPrank();
    }

    function test_swapEthCurveBridge() public {
        uint256 amountIn = 500_0000; // 0.05 BTC
        address fromToken = WBTC_ADDRESS_ETH;
        address receivedToken = WETH_ADDRESS_ETH;
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 1;
        uint256 i = 1;
        uint256 j = 2;
        address pool = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;
        uint256 toAmountMin = 5e17;

        bytes memory swapPayload = abi.encode(
            bytes1(0x02), // swapType 2 on Curve
            fromToken,
            receivedToken,
            i,
            j,
            pool,
            amountIn,
            toAmountMin
        );
        bytes memory bridgePayload = abi.encode(
            sender,
            EPOCH_ID,
            EARTHQUAKE_VAULT
        );

        vm.startPrank(sender);
        deal(WBTC_ADDRESS_ETH, sender, amountIn);
        assertEq(IERC20(WBTC_ADDRESS_ETH).balanceOf(sender), amountIn);

        IERC20(WBTC_ADDRESS_ETH).approve(address(zapFrom), amountIn);
        zapFrom.swapAndBridge{value: 0.1 ether}(
            amountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
            0x04, // Curve dexId
            swapPayload,
            bridgePayload
        );

        assertEq(IERC20(WBTC_ADDRESS_ETH).balanceOf(sender), 0);
        vm.stopPrank();
    }

    function test_swapEthCurveMulti() public {
        uint256 amountIn = 100e6;
        address fromToken = USDC_ADDRESS_ETH;
        address receivedToken = address(0);
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 1;
        (
            bytes memory swapPayload,
            bytes memory bridgePayload
        ) = _setupCurveMultiBridge(amountIn, fromToken, receivedToken);
        vm.startPrank(sender);
        deal(USDC_ADDRESS_ETH, sender, amountIn);
        assertEq(IERC20(USDC_ADDRESS_ETH).balanceOf(sender), amountIn);

        IERC20(USDC_ADDRESS_ETH).approve(address(zapFrom), amountIn);
        zapFrom.swapAndBridge{value: 0.1 ether}(
            amountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
            0x04, // Curve dexId
            swapPayload,
            bridgePayload
        );

        assertEq(IERC20(USDC_ADDRESS_ETH).balanceOf(sender), 0);
        vm.stopPrank();
    }

    function test_swapEthBalancerbridge() public {
        uint256 amountIn = 100e18;
        uint256 toAmountMin = 1e16;
        bytes32 poolId = 0x0b09dea16768f0799065c475be02919503cb2a3500020000000000000000001a;
        address fromToken = DAI_ADDRESS_ETH;
        address receivedToken = WETH_ADDRESS_ETH;
        uint256 deadline = block.timestamp + 1000;

        uint16 srcPoolId = 1;
        uint16 dstPoolId = 1;

        IBalancer.SingleSwap memory singleSwap = IBalancer.SingleSwap({
            poolId: poolId,
            kind: IBalancer.SwapKind.GIVEN_IN,
            assetIn: fromToken,
            assetOut: receivedToken,
            amount: amountIn,
            userData: ""
        });
        IBalancer.Funds memory funds = IBalancer.Funds({
            sender: payable(address(zapFrom)),
            fromInternalBalance: false,
            recipient: payable(address(zapFrom)),
            toInternalBalance: false
        });
        bytes memory swapPayload = abi.encodeWithSelector(
            IBalancer.swap.selector,
            singleSwap,
            funds,
            toAmountMin,
            deadline
        );
        bytes memory bridgePayload = abi.encode(
            sender,
            EPOCH_ID,
            EARTHQUAKE_VAULT
        );

        vm.startPrank(sender);
        deal(DAI_ADDRESS_ETH, sender, amountIn);
        assertEq(IERC20(DAI_ADDRESS_ETH).balanceOf(sender), amountIn);

        IERC20(DAI_ADDRESS_ETH).approve(address(zapFrom), amountIn);
        zapFrom.swapAndBridge{value: 0.1 ether}(
            amountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
            0x05, // Balancer dexId
            swapPayload,
            bridgePayload
        );

        assertEq(IERC20(DAI_ADDRESS_ETH).balanceOf(sender), 0);
        vm.stopPrank();
    }

    function test_swapEthMultiBalancerbridge() public {
        uint256 amountIn = 100e6;
        uint256 toAmountMin = 1e16;
        bytes32 firstPoolId = 0x79c58f70905f734641735bc61e45c19dd9ad60bc0000000000000000000004e7;
        bytes32 secondPoolId = 0x0b09dea16768f0799065c475be02919503cb2a3500020000000000000000001a;
        address fromToken = USDC_ADDRESS_ETH;
        address connectorToken = DAI_ADDRESS_ETH;
        address receivedToken = WETH_ADDRESS_ETH;

        // NOTE: Indexes for each swap e.g. [0] is assetIn and [1] is assetOut etc.
        uint256[] memory assetIndexes = new uint256[](3);
        assetIndexes[0] = 0;
        assetIndexes[1] = 1;
        assetIndexes[2] = 2;

        uint16 srcPoolId = 1;
        uint16 dstPoolId = 1;

        bytes memory swapPayload = _setupBalancerMultiBridge(
            firstPoolId,
            secondPoolId,
            amountIn,
            toAmountMin,
            fromToken,
            connectorToken,
            receivedToken,
            block.timestamp + 1000,
            assetIndexes
        );
        bytes memory bridgePayload = abi.encode(
            sender,
            EPOCH_ID,
            EARTHQUAKE_VAULT
        );

        vm.startPrank(sender);
        deal(USDC_ADDRESS_ETH, sender, amountIn);
        assertEq(IERC20(USDC_ADDRESS_ETH).balanceOf(sender), amountIn);

        IERC20(USDC_ADDRESS_ETH).approve(address(zapFrom), amountIn);
        zapFrom.swapAndBridge{value: 0.2 ether}(
            amountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
            0x05, // Balancer dexId
            swapPayload,
            bridgePayload
        );

        assertEq(IERC20(USDC_ADDRESS_ETH).balanceOf(sender), 0);
        vm.stopPrank();
    }

    /////////////////////////////////////////
    //                 ERRORS              //
    /////////////////////////////////////////
    function testErrors_zapFromConstructor() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            ZapFrom.Config(
                address(0),
                STARGATE_ROUTER_USINGETH,
                LAYER_ZERO_ROUTER_LOCAL,
                y2kArbRouter,
                UNISWAP_V2_FACTORY,
                SUSHI_V2_FACTORY_ETH,
                UNISWAP_V3_FACTORY,
                BALANCER_VAULT,
                WETH_ADDRESS_ETH,
                PERMIT_2,
                PRIMARY_INIT_HASH_ETH,
                SECONDARY_INIT_HASH_ETH
            )
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            ZapFrom.Config(
                STARGATE_ROUTER,
                address(0),
                LAYER_ZERO_ROUTER_LOCAL,
                y2kArbRouter,
                UNISWAP_V2_FACTORY,
                SUSHI_V2_FACTORY_ETH,
                UNISWAP_V3_FACTORY,
                BALANCER_VAULT,
                WETH_ADDRESS_ETH,
                PERMIT_2,
                PRIMARY_INIT_HASH_ETH,
                SECONDARY_INIT_HASH_ETH
            )
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            ZapFrom.Config(
                STARGATE_ROUTER,
                STARGATE_ROUTER_USINGETH,
                address(0),
                y2kArbRouter,
                UNISWAP_V2_FACTORY,
                SUSHI_V2_FACTORY_ETH,
                UNISWAP_V3_FACTORY,
                BALANCER_VAULT,
                WETH_ADDRESS_ETH,
                PERMIT_2,
                PRIMARY_INIT_HASH_ETH,
                SECONDARY_INIT_HASH_ETH
            )
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            ZapFrom.Config(
                STARGATE_ROUTER,
                STARGATE_ROUTER_USINGETH,
                LAYER_ZERO_ROUTER_LOCAL,
                address(0),
                UNISWAP_V2_FACTORY,
                SUSHI_V2_FACTORY_ETH,
                UNISWAP_V3_FACTORY,
                BALANCER_VAULT,
                WETH_ADDRESS_ETH,
                PERMIT_2,
                PRIMARY_INIT_HASH_ETH,
                SECONDARY_INIT_HASH_ETH
            )
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            ZapFrom.Config(
                STARGATE_ROUTER,
                STARGATE_ROUTER_USINGETH,
                LAYER_ZERO_ROUTER_LOCAL,
                y2kArbRouter,
                address(0),
                SUSHI_V2_FACTORY_ETH,
                UNISWAP_V3_FACTORY,
                BALANCER_VAULT,
                WETH_ADDRESS_ETH,
                PERMIT_2,
                PRIMARY_INIT_HASH_ETH,
                SECONDARY_INIT_HASH_ETH
            )
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            ZapFrom.Config(
                STARGATE_ROUTER,
                STARGATE_ROUTER_USINGETH,
                LAYER_ZERO_ROUTER_LOCAL,
                y2kArbRouter,
                UNISWAP_V2_FACTORY,
                address(0),
                UNISWAP_V3_FACTORY,
                BALANCER_VAULT,
                WETH_ADDRESS_ETH,
                PERMIT_2,
                PRIMARY_INIT_HASH_ETH,
                SECONDARY_INIT_HASH_ETH
            )
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            ZapFrom.Config(
                STARGATE_ROUTER,
                STARGATE_ROUTER_USINGETH,
                LAYER_ZERO_ROUTER_LOCAL,
                y2kArbRouter,
                UNISWAP_V2_FACTORY,
                SUSHI_V2_FACTORY_ETH,
                address(0),
                BALANCER_VAULT,
                WETH_ADDRESS_ETH,
                PERMIT_2,
                PRIMARY_INIT_HASH_ETH,
                SECONDARY_INIT_HASH_ETH
            )
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            ZapFrom.Config(
                STARGATE_ROUTER,
                STARGATE_ROUTER_USINGETH,
                LAYER_ZERO_ROUTER_LOCAL,
                y2kArbRouter,
                UNISWAP_V2_FACTORY,
                SUSHI_V2_FACTORY_ETH,
                UNISWAP_V3_FACTORY,
                address(0),
                WETH_ADDRESS_ETH,
                PERMIT_2,
                PRIMARY_INIT_HASH_ETH,
                SECONDARY_INIT_HASH_ETH
            )
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            ZapFrom.Config(
                STARGATE_ROUTER,
                STARGATE_ROUTER_USINGETH,
                LAYER_ZERO_ROUTER_LOCAL,
                y2kArbRouter,
                UNISWAP_V2_FACTORY,
                SUSHI_V2_FACTORY_ETH,
                UNISWAP_V3_FACTORY,
                BALANCER_VAULT,
                address(0),
                PERMIT_2,
                PRIMARY_INIT_HASH_ETH,
                SECONDARY_INIT_HASH_ETH
            )
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            ZapFrom.Config(
                STARGATE_ROUTER,
                STARGATE_ROUTER_USINGETH,
                LAYER_ZERO_ROUTER_LOCAL,
                y2kArbRouter,
                UNISWAP_V2_FACTORY,
                SUSHI_V2_FACTORY_ETH,
                UNISWAP_V3_FACTORY,
                BALANCER_VAULT,
                WETH_ADDRESS_ETH,
                address(0),
                PRIMARY_INIT_HASH_ETH,
                SECONDARY_INIT_HASH_ETH
            )
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            ZapFrom.Config(
                STARGATE_ROUTER,
                STARGATE_ROUTER_USINGETH,
                LAYER_ZERO_ROUTER_LOCAL,
                y2kArbRouter,
                UNISWAP_V2_FACTORY,
                SUSHI_V2_FACTORY_ETH,
                UNISWAP_V3_FACTORY,
                BALANCER_VAULT,
                WETH_ADDRESS_ETH,
                PERMIT_2,
                bytes(""),
                SECONDARY_INIT_HASH_ETH
            )
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            ZapFrom.Config(
                STARGATE_ROUTER,
                STARGATE_ROUTER_USINGETH,
                LAYER_ZERO_ROUTER_LOCAL,
                y2kArbRouter,
                UNISWAP_V2_FACTORY,
                SUSHI_V2_FACTORY_ETH,
                UNISWAP_V3_FACTORY,
                BALANCER_VAULT,
                WETH_ADDRESS_ETH,
                PERMIT_2,
                PRIMARY_INIT_HASH_ETH,
                bytes("")
            )
        );
    }

    function testErrors_bridgeInvalidInputs() public {
        uint256 amountIn = 1;
        address fromToken = USDC_ADDRESS_ETH;
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 2;
        bytes memory payload = abi.encode(address(0), 0, 0);

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom.bridge(amountIn, fromToken, srcPoolId, dstPoolId, payload);

        uint256 zeroAmountIn = 0;
        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom.bridge{value: amountIn}(
            zeroAmountIn,
            fromToken,
            srcPoolId,
            dstPoolId,
            payload
        );
    }

    function testErrors_permitSwapBridgeInvalidInputs() public {
        uint256 amountIn = 1;
        address receivedToken = USDT_ADDRESS_ETH;
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 2;
        bytes1 dexId = 0x01;
        ISignatureTransfer.TokenPermissions
            memory permissions = ISignatureTransfer.TokenPermissions(
                address(0),
                0
            );
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer
            .PermitTransferFrom(permissions, 0, 0);
        ISignatureTransfer.SignatureTransferDetails
            memory transferDetails = ISignatureTransfer
                .SignatureTransferDetails(address(0), 0);
        bytes memory sig = abi.encode(bytes(""));
        bytes memory swapPayload = abi.encode(bytes(""));
        bytes memory bridgePayload = abi.encode(address(0), 0, 0);

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom.permitSwapAndBridge(
            receivedToken,
            srcPoolId,
            dstPoolId,
            dexId,
            permit,
            transferDetails,
            sig,
            swapPayload,
            bridgePayload
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom.permitSwapAndBridge{value: amountIn}(
            receivedToken,
            srcPoolId,
            dstPoolId,
            dexId,
            permit,
            transferDetails,
            sig,
            swapPayload,
            bridgePayload
        );
    }

    function testErrors_swapBridgeInvalidInputs() public {
        uint256 amountIn = 1;
        address fromToken = USDC_ADDRESS_ETH;
        address receivedToken = USDT_ADDRESS_ETH;
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 2;
        bytes1 dexId = 0x01;
        bytes memory swapPayload = abi.encode(bytes(""));
        bytes memory bridgePayload = abi.encode(address(0), 0, 0);

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom.swapAndBridge(
            amountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
            dexId,
            swapPayload,
            bridgePayload
        );

        uint256 zeroAmountIn = 0;
        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom.swapAndBridge{value: amountIn}(
            zeroAmountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
            dexId,
            swapPayload,
            bridgePayload
        );
    }
}
