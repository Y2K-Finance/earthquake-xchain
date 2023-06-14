// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Helper} from "./Helper.sol";
import {ZapDest} from "../../src/bridgeZaps/zapDest.sol";
import {ZapFrom} from "../../src/bridgeZaps/zapFrom.sol";

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IEarthQuakeVault, IERC1155} from "../utils/Interfaces.sol";

contract BridgeHelper is Helper {
    address stargateRelayer;
    address layerZeroRelayer;

    ZapDest public zapDest;
    ZapFrom public zapFrom;

    uint256 mainnetFork;
    uint256 arbitrumFork;

    event ReceivedDeposit(address token, address receiver, uint256 amount);
    event ReceivedWithdrawal(
        bytes1 orderType,
        address receiver,
        uint256 amount
    );
    event TrustedRemoteAdded(
        uint16 chainId,
        bytes trustedAddress,
        address sender
    );
    event TokenToHopBridgeSet(
        address[] tokens,
        address[] bridges,
        address sender
    );

    /////////////////////////////////////////
    //               CONFIG                //
    /////////////////////////////////////////

    function setUpArbitrum() public virtual {
        mainnetFork = vm.createSelectFork(MAINNET_RPC_URL, 17269532);
        arbitrumFork = vm.createFork(ARBITRUM_RPC_URL);
        vm.selectFork(arbitrumFork);
        vm.warp(EPOCH_BEGIN - 1);

        stargateRelayer = sender;
        layerZeroRelayer = secondSender;

        zapDest = new ZapDest(
            stargateRelayer,
            layerZeroRelayer,
            EARTHQUAKE_VAULT,
            CELER_BRIDGE,
            HYPHEN_BRIDGE,
            CAMELOT_FACTORY,
            SUSHI_V2_FACTORY,
            UNISWAP_V3_FACTORY
        );

        vm.label(address(0x01), "Sender");
        vm.label(address(0x02), "SecondSender");
        vm.label(USDC_ADDRESS, "USDC");
        vm.label(WETH_ADDRESS, "WETH");
        vm.label(address(zapDest), "ZapDest");
        vm.label(CELER_BRIDGE, "CELR");
        vm.label(HYPHEN_BRIDGE, "HYPHEN");
    }

    function setUpMainnet() public {
        mainnetFork = vm.createSelectFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        zapFrom = new ZapFrom(
            STARGATE_ROUTER,
            STARGATE_ROUTER_USINGETH,
            LAYER_ZERO_ROUTER_REMOTE,
            LAYER_ZERO_ROUTER_LOCAL,
            y2kArbRouter,
            UNISWAP_V2_FACTORY,
            SUSHI_V2_FACTORY_ETH,
            UNISWAP_V3_FACTORY,
            BALANCER_VAULT
        );

        vm.label(address(0x01), "Sender");
        vm.label(address(0x02), "SecondSender");
        vm.label(USDC_ADDRESS_ETH, "USDC");
        vm.label(WETH_ADDRESS_ETH, "WETH");
        vm.label(address(zapFrom), "ZapFrom");
        vm.label(STARGATE_ROUTER, "STG ERC20");
        vm.label(STARGATE_ROUTER_USINGETH, "STG ETH");
    }

    /////////////////////////////////////////
    //         BRIDGE HELPERS              //
    /////////////////////////////////////////
    function setupSgReceiveDeposit(
        address sender,
        address receiver,
        address token,
        uint256 id
    )
        internal
        returns (
            bytes memory srcAddress,
            uint64 nonce,
            uint256 fromAmount,
            bytes memory payload,
            uint256 chainId
        )
    {
        fromAmount = 1e18;
        deal(token, sender, fromAmount);
        assertEq(IERC20(token).balanceOf(sender), fromAmount);

        vm.prank(sender);
        IERC20(token).transfer(address(zapDest), fromAmount);

        srcAddress = abi.encode(stargateRelayer); // Set to sender address
        nonce = 0;
        payload = abi.encode(receiver, id);
        chainId = 1; // Set to 1 for mainnet

        assertEq(IERC20(token).balanceOf(sender), 0);
        assertEq(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 0);
    }

    function _setupLzReceiveWithdraw(
        address sender,
        address receiver,
        uint256 epochId
    )
        internal
        pure
        returns (bytes memory srcAddress, uint64 nonce, bytes memory payload)
    {
        srcAddress = abi.encode(sender);
        nonce = 0;
        bytes1 funcSelector = 0x01;
        bytes1 bridgeId = 0x00;

        payload = abi.encode(funcSelector, bridgeId, receiver, epochId);
    }

    function _depositToVault(address _depositor) internal returns (uint256) {
        address token = WETH_ADDRESS;
        (
            bytes memory srcAddress,
            uint64 nonce,
            uint256 amount,
            bytes memory payload,
            uint256 chainId
        ) = setupSgReceiveDeposit(stargateRelayer, _depositor, token, EPOCH_ID);
        vm.prank(stargateRelayer);
        zapDest.sgReceive(
            uint16(chainId),
            srcAddress,
            nonce,
            token,
            amount,
            payload
        );
        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(zapDest)), 0);
        assertGe(
            IERC1155(EARTHQUAKE_VAULT).balanceOf(address(zapDest), EPOCH_ID),
            1
        );
        return amount;
    }

    /////////////////////////////////////////
    //         BRIDGE & SWAP HELPERS       //
    /////////////////////////////////////////
    function _setupSwapV2AndBridge(
        address sender,
        address receiver,
        uint256 epochId,
        bytes1 bridgeId,
        bytes1 swapId,
        bytes1 dexId,
        address toToken
    )
        internal
        pure
        returns (bytes memory srcAddress, uint64 nonce, bytes memory payload)
    {
        srcAddress = abi.encode(sender);
        nonce = 0;
        bytes1 funcSelector = 0x03;
        // NOTE: Using 1 eth deposit as standard
        uint256 toAmountMin = (1700e6 * 99) / 100;

        if (bridgeId == 0x01) {
            uint256 celerSlippage = 10e6;
            payload = abi.encode(
                funcSelector,
                bridgeId,
                receiver,
                epochId,
                swapId,
                toAmountMin,
                dexId,
                toToken,
                celerSlippage
            );
        } else if (bridgeId == 0x02) {
            payload = abi.encode(
                funcSelector,
                bridgeId,
                receiver,
                epochId,
                swapId,
                toAmountMin,
                dexId,
                toToken
            );
        } else if (bridgeId == 0x03) {
            uint256 hopSlippage = 100;
            // NOTE: Bonder fee used = max(amount.mul(2).div(10000), minBonderFeeAbsolute);
            uint256 bonderFee = (toAmountMin * 4) / 10000;
            payload = abi.encode(
                funcSelector,
                bridgeId,
                receiver,
                epochId,
                swapId,
                toAmountMin,
                dexId,
                toToken,
                hopSlippage,
                bonderFee
            );
        }
    }

    function _setupSwapV3AndBridge(
        address sender,
        address receiver,
        uint256 epochId,
        bytes1 bridgeId,
        bytes1 swapId,
        bytes1 dexId,
        address toToken
    )
        internal
        pure
        returns (bytes memory srcAddress, uint64 nonce, bytes memory payload)
    {
        srcAddress = abi.encode(sender);
        nonce = 0;
        bytes1 funcSelector = 0x03;
        uint256 toAmountMin = (10e8 * 99) / 100;
        uint24 fee = 500;

        if (bridgeId == 0x01) {
            uint256 celerSlippage = 10e6;
            payload = abi.encode(
                funcSelector,
                bridgeId,
                receiver,
                epochId,
                swapId,
                toAmountMin,
                dexId,
                toToken,
                fee,
                celerSlippage
            );
        } else if (bridgeId == 0x02) {
            payload = abi.encode(
                funcSelector,
                bridgeId,
                receiver,
                epochId,
                swapId,
                toAmountMin,
                dexId,
                toToken,
                fee
            );
        } else if (bridgeId == 0x03) {
            uint256 hopSlippage = 100;
            // NOTE: Bonder fee used = max(amount.mul(2).div(10000), minBonderFeeAbsolute);
            uint256 bonderFee = (toAmountMin * 4) / 10000;
            payload = abi.encode(
                funcSelector,
                bridgeId,
                receiver,
                epochId,
                swapId,
                toAmountMin,
                dexId,
                toToken,
                fee,
                hopSlippage,
                bonderFee
            );
        }
    }
}
