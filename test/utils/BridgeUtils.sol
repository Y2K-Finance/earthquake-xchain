// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Helper} from "./Helper.sol";
import {ZapDest} from "../../src/bridgeZaps/zapDest.sol";

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IEarthQuakeVault, IERC1155} from "../utils/Interfaces.sol";

contract BridgeHelper is Helper {
    address stargateRelayer;
    address layerZeroRelayer;

    ZapDest public zapDest;

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

    /////////////////////////////////////////
    //               CONFIG                //
    /////////////////////////////////////////

    function setUp() public virtual {
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
}
