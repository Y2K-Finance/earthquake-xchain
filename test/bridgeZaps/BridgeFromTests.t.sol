// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "forge-std/Test.sol";
import {BridgeHelper} from "../utils/BridgeUtils.sol";
import {ZapFrom} from "../../src/bridgeZaps/zapFrom.sol";
import {IErrors} from "../../src/interfaces/IErrors.sol";
import {BytesLib} from "../../src/libraries/BytesLib.sol";
import {IEarthQuakeVault, IERC1155, IEarthquakeController, IStargateRouter} from "../utils/Interfaces.sol";

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
        assertEq(zapFrom.stargateRouter(), STARGATE_ROUTER);
        assertEq(zapFrom.stargateRouterEth(), STARGATE_ROUTER_USINGETH);
        assertEq(zapFrom.uniswapV2ForkFactory(), UNISWAP_V2_FACTORY);
        assertEq(zapFrom.sushiFactory(), SUSHI_V2_FACTORY_ETH);
        assertEq(zapFrom.uniswapV3Factory(), UNISWAP_V3_FACTORY);
        assertEq(zapFrom.balancerVault(), BALANCER_VAULT);
    }

    /////////////////////////////////////////
    //         BRIDGE FUNCTIONS            //
    /////////////////////////////////////////
    // TODO: Error is "Stargate: local chainPath does not exist' - what is the poolId?
    function test_bridgeETH() public {
        uint256 amountIn = 1 ether;
        address fromToken = address(0);
        uint16 srcPoolId = 13; // What should this be?
        uint16 dstPoolId = 13; // What should this be?
        bytes memory payload = abi.encode(address(0x01), 0);
        uint256 balance = address(this).balance;

        // TODO: Failed to refund error - resolve this how?
        zapFrom.bridge{value: 1.005 ether}(
            amountIn,
            fromToken,
            srcPoolId,
            dstPoolId,
            payload
        );

        assertEq(address(this).balance, balance - 1.1 ether);
    }

    function test_bridgeERC20() public {
        uint256 amountIn = 1000e6;
        address fromToken = USDC_ADDRESS_ETH;
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 1;
        bytes memory payload = abi.encode(address(0x01), 0);

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

    function test_withdraw() public {}

    /////////////////////////////////////////
    //       BRIDGE & SWAP FUNCTIONS       //
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
        uint256 toAmountMin = 100e6;
        bytes memory swapPayload = abi.encode(dexId, path, toAmountMin);
        bytes memory bridgePayload = abi.encode(address(0x01), 0);

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
            swapPayload,
            bridgePayload
        );

        assertEq(IERC20(USDT_ADDRESS_ETH).balanceOf(sender), 0);
        vm.stopPrank();
    }

    function test_swapSushibridge() public {}

    function test_swapUniV3bridge() public {}

    function test_swapBalancerbridge() public {}

    /////////////////////////////////////////
    //                 ERRORS              //
    /////////////////////////////////////////
    function testErrors_zapFromConstructor() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            address(0),
            STARGATE_ROUTER_USINGETH,
            LAYER_ZERO_ROUTER_REMOTE,
            LAYER_ZERO_ROUTER_LOCAL,
            y2kArbRouter,
            UNISWAP_V2_FACTORY,
            SUSHI_V2_FACTORY_ETH,
            UNISWAP_V3_FACTORY,
            BALANCER_VAULT
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            STARGATE_ROUTER,
            address(0),
            LAYER_ZERO_ROUTER_REMOTE,
            LAYER_ZERO_ROUTER_LOCAL,
            y2kArbRouter,
            UNISWAP_V2_FACTORY,
            SUSHI_V2_FACTORY_ETH,
            UNISWAP_V3_FACTORY,
            BALANCER_VAULT
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            STARGATE_ROUTER,
            STARGATE_ROUTER_USINGETH,
            address(0),
            LAYER_ZERO_ROUTER_LOCAL,
            y2kArbRouter,
            UNISWAP_V2_FACTORY,
            SUSHI_V2_FACTORY_ETH,
            UNISWAP_V3_FACTORY,
            BALANCER_VAULT
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            STARGATE_ROUTER,
            STARGATE_ROUTER_USINGETH,
            LAYER_ZERO_ROUTER_REMOTE,
            address(0),
            y2kArbRouter,
            UNISWAP_V2_FACTORY,
            SUSHI_V2_FACTORY_ETH,
            UNISWAP_V3_FACTORY,
            BALANCER_VAULT
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            STARGATE_ROUTER,
            STARGATE_ROUTER_USINGETH,
            LAYER_ZERO_ROUTER_REMOTE,
            LAYER_ZERO_ROUTER_LOCAL,
            address(0),
            UNISWAP_V2_FACTORY,
            SUSHI_V2_FACTORY_ETH,
            UNISWAP_V3_FACTORY,
            BALANCER_VAULT
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            STARGATE_ROUTER,
            STARGATE_ROUTER_USINGETH,
            LAYER_ZERO_ROUTER_REMOTE,
            LAYER_ZERO_ROUTER_LOCAL,
            y2kArbRouter,
            address(0),
            SUSHI_V2_FACTORY_ETH,
            UNISWAP_V3_FACTORY,
            BALANCER_VAULT
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            STARGATE_ROUTER,
            STARGATE_ROUTER_USINGETH,
            LAYER_ZERO_ROUTER_REMOTE,
            LAYER_ZERO_ROUTER_LOCAL,
            y2kArbRouter,
            UNISWAP_V2_FACTORY,
            address(0),
            UNISWAP_V3_FACTORY,
            BALANCER_VAULT
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            STARGATE_ROUTER,
            STARGATE_ROUTER_USINGETH,
            LAYER_ZERO_ROUTER_REMOTE,
            LAYER_ZERO_ROUTER_LOCAL,
            y2kArbRouter,
            UNISWAP_V2_FACTORY,
            SUSHI_V2_FACTORY_ETH,
            address(0),
            BALANCER_VAULT
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom = new ZapFrom(
            STARGATE_ROUTER,
            STARGATE_ROUTER_USINGETH,
            LAYER_ZERO_ROUTER_REMOTE,
            LAYER_ZERO_ROUTER_LOCAL,
            y2kArbRouter,
            UNISWAP_V2_FACTORY,
            SUSHI_V2_FACTORY_ETH,
            UNISWAP_V3_FACTORY,
            address(0)
        );
    }

    function testErrors_bridgeInvalidInputs() public {
        uint256 amountIn = 1;
        address fromToken = USDC_ADDRESS_ETH;
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 2;
        bytes memory payload = abi.encode(bytes(""));

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
        address fromToken = USDC_ADDRESS_ETH;
        address receivedToken = USDT_ADDRESS_ETH;
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 2;
        bytes memory swapPayload = abi.encode(bytes(""));
        bytes memory bridgePayload = abi.encode(bytes(""));

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom.permitSwapAndBridge(
            amountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
            swapPayload,
            bridgePayload
        );

        uint256 zeroAmountIn = 0;
        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom.permitSwapAndBridge{value: amountIn}(
            zeroAmountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
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
        bytes memory swapPayload = abi.encode(bytes(""));
        bytes memory bridgePayload = abi.encode(bytes(""));

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapFrom.swapAndBridge(
            amountIn,
            fromToken,
            receivedToken,
            srcPoolId,
            dstPoolId,
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
            swapPayload,
            bridgePayload
        );
    }
}
