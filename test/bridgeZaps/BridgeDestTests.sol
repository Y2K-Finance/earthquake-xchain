// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "forge-std/Test.sol";
import {BridgeHelper} from "../utils/BridgeUtils.sol";
import {ZapDest} from "../../src/bridgeZaps/zapDest.sol";
import {IErrors} from "../../src/interfaces/IErrors.sol";
import {BytesLib} from "../../src/libraries/BytesLib.sol";
import {IEarthQuakeVault, IERC1155, IEarthquakeController} from "../utils/Interfaces.sol";

contract BridgeDestTests is BridgeHelper {
    using BytesLib for bytes;

    /////////////////////////////////////////
    //               CONFIG                //
    /////////////////////////////////////////
    function forkAndConfig() public {
        assertEq(vm.activeFork(), arbitrumFork);
    }

    /////////////////////////////////////////
    //               HELPERS                //
    /////////////////////////////////////////
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

    function _setupSwapAndBridge(
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
    }

    /////////////////////////////////////////
    //               STATE VARS            //
    /////////////////////////////////////////
    function test_stateVars() public {
        assertEq(zapDest.STARGATE_RELAYER(), stargateRelayer);
        assertEq(zapDest.LAYER_ZERO_ENDPOINT(), layerZeroRelayer);
        assertEq(address(zapDest.EARTHQUAKE_VAULT()), EARTHQUAKE_VAULT);
        assertEq(address(zapDest.celerBridge()), CELER_BRIDGE);
        assertEq(address(zapDest.hyphenBridge()), HYPHEN_BRIDGE);
    }

    /////////////////////////////////////////
    //              VAULT FUNCTIONS        //
    /////////////////////////////////////////
    function test_setTrustedRemoteLookup() public {
        uint16 srcChainId = 1;
        bytes memory trustedAddress = abi.encode(layerZeroRelayer);

        vm.expectEmit(true, true, true, false);
        emit TrustedRemoteAdded(srcChainId, trustedAddress, address(this));
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);

        assertEq(zapDest.trustedRemoteLookup(srcChainId), trustedAddress);
    }

    function test_depositWithSTG() public {
        address token = WETH_ADDRESS;
        (
            bytes memory srcAddress,
            uint64 nonce,
            uint256 amount,
            bytes memory payload,
            uint256 chainId
        ) = setupSgReceiveDeposit(stargateRelayer, sender, token, EPOCH_ID);

        vm.startPrank(stargateRelayer);
        vm.expectEmit(true, true, true, false);
        emit ReceivedDeposit(token, address(zapDest), amount);
        zapDest.sgReceive(
            uint16(chainId),
            srcAddress,
            nonce,
            token,
            amount,
            payload
        );

        assertEq(zapDest.addressToIdToAmount(sender, EPOCH_ID), amount);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(zapDest)), 0);
        assertGe(
            IERC1155(EARTHQUAKE_VAULT).balanceOf(address(zapDest), EPOCH_ID),
            1
        );
    }

    function test_withdrawWithLZ() public {
        // Deposits to the valut as the sender
        uint256 amount = _depositToVault(sender);
        uint16 srcChainId = 1;

        // Set the trusted remote
        bytes memory trustedAddress = abi.encode(layerZeroRelayer);
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);

        // Calculate amount received in withdraw
        vm.roll(block.timestamp);
        uint256 amountOut = (IEarthQuakeVault(EARTHQUAKE_VAULT).previewWithdraw(
            EPOCH_ID,
            amount
        ) * 99) / 100;

        // Withdraw from vault
        (
            bytes memory srcAddress,
            uint64 nonce,
            bytes memory payload
        ) = _setupLzReceiveWithdraw(layerZeroRelayer, sender, EPOCH_ID);
        vm.startPrank(layerZeroRelayer);
        vm.expectEmit(true, true, true, false);
        emit ReceivedWithdrawal(0x01, sender, amount); // 0x01 is the funcSelector for withdraw
        zapDest.lzReceive(srcChainId, srcAddress, nonce, payload);

        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(zapDest)), 0);
        assertGe(IERC20(WETH_ADDRESS).balanceOf(sender), amountOut);
        assertEq(
            IERC1155(EARTHQUAKE_VAULT).balanceOf(address(zapDest), EPOCH_ID),
            0
        );
    }

    function test_withdrawOnDest() public {
        // Deposits to the valut as the sender
        uint256 amount = _depositToVault(sender);
        bytes1 funcSelector = 0x01;
        bytes1 bridgeId = 0x00;
        uint16 srcChainId = 1;

        // Calculate amount received in withdraw
        vm.roll(block.timestamp);
        uint256 amountOut = (IEarthQuakeVault(EARTHQUAKE_VAULT).previewWithdraw(
            EPOCH_ID,
            amount
        ) * 99) / 100;

        // Withdraw from vault
        vm.startPrank(sender);
        vm.expectEmit(true, true, true, false);
        emit ReceivedWithdrawal(0x01, sender, amount); // 0x01 is the funcSelector for withdraw
        zapDest.withdraw(
            funcSelector,
            bridgeId,
            EPOCH_ID,
            srcChainId,
            bytes("")
        );

        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(zapDest)), 0);
        assertGe(IERC20(WETH_ADDRESS).balanceOf(sender), amountOut);
    }

    /////////////////////////////////////////
    //              BRIDGE FUNCTIONS       //
    /////////////////////////////////////////
    function test_withdrawAndBridgeWithCeler() public {
        // Deposits to the valut as the sender
        _depositToVault(sender);
        bytes1 funcSelector = 0x02;
        bytes1 bridgeId = 0x01;
        uint16 srcChainId = 1;
        bytes memory payload = abi.encode(1e6);

        // Withdraw from vault
        vm.roll(block.timestamp);
        vm.startPrank(sender);
        zapDest.withdraw(funcSelector, bridgeId, EPOCH_ID, srcChainId, payload);

        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(zapDest)), 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(sender), 0);
        assertEq(
            IERC1155(EARTHQUAKE_VAULT).balanceOf(address(zapDest), EPOCH_ID),
            0
        );
    }

    // TODO: Logic working - test after swap or with another deposit asset
    function test_withdrawAndBridgeWithHyphen() private {
        // Deposits to the valut as the sender
        _depositToVault(sender);
        bytes1 funcSelector = 0x02;
        bytes1 bridgeId = 0x02;
        uint16 srcChainId = 1;

        // Withdraw from vault
        vm.roll(block.timestamp);
        vm.startPrank(sender);
        zapDest.withdraw(
            funcSelector,
            bridgeId,
            EPOCH_ID,
            srcChainId,
            bytes("")
        );

        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(zapDest)), 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(sender), 0);
        assertEq(
            IERC1155(EARTHQUAKE_VAULT).balanceOf(address(zapDest), EPOCH_ID),
            0
        );
    }

    // TODO: Need to test with after a swap or with a different deposit asset
    function test_withdrawAndBridgeWithHop() private {
        // Deposits to the valut as the sender
        _depositToVault(sender);
        bytes1 funcSelector = 0x02;
        bytes1 bridgeId = 0x03;
        uint16 srcChainId = 1;

        // Withdraw from vault
        vm.roll(block.timestamp);
        vm.startPrank(sender);
        zapDest.withdraw(
            funcSelector,
            bridgeId,
            EPOCH_ID,
            srcChainId,
            bytes("")
        );

        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(zapDest)), 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(sender), 0);
        assertEq(
            IERC1155(EARTHQUAKE_VAULT).balanceOf(address(zapDest), EPOCH_ID),
            0
        );
    }

    /////////////////////////////////////////
    //       BRIDGE & SWAP FUNCTIONS       //
    /////////////////////////////////////////
    function test_withdrawSwapCamelotBridgeCeler() public {
        // Deposits to the valut as the sender
        uint256 amount = _depositToVault(sender);
        uint16 srcChainId = 1;

        // Set the trusted remote
        bytes memory trustedAddress = abi.encode(layerZeroRelayer);
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);

        // Calculate amount received in withdraw
        vm.roll(block.timestamp);
        bytes1 swapId = 0x01;
        bytes1 bridgeId = 0x02;
        bytes1 dexId = 0x01;
        address toToken = USDC_ADDRESS;

        (
            bytes memory srcAddress,
            uint64 nonce,
            bytes memory payload
        ) = _setupSwapAndBridge(
                layerZeroRelayer,
                sender,
                EPOCH_ID,
                bridgeId,
                swapId,
                dexId,
                toToken
            );

        // Payload outputs: (1) bytes1 funcSelector: 0x03, (2) bytes1 bridgeId: 0x01, (3) address receiver: address(0x01)
        // (4) uint256 epochId: 1684713600, (5) bytes1 swapId: 0x01, (6) uint256 toAmountMin: 10e8, (7) bytes1 dexId: 0x01
        vm.startPrank(layerZeroRelayer);
        vm.expectEmit(true, true, true, false);
        emit ReceivedWithdrawal(0x01, sender, amount); // 0x01 is the funcSelector for withdraw
        zapDest.lzReceive(srcChainId, srcAddress, nonce, payload);

        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(zapDest)), 0);
        assertEq(
            IERC1155(EARTHQUAKE_VAULT).balanceOf(address(zapDest), EPOCH_ID),
            0
        );
    }

    function test_withdrawSwapSushiBridgeHop() private {
        // Deposits to the valut as the sender
        uint256 amount = _depositToVault(sender);
        uint16 srcChainId = 1;

        // Set the trusted remote
        bytes memory trustedAddress = abi.encode(layerZeroRelayer);
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);

        // Set the hop bridge
        address[] memory tokens = new address[](1);
        address[] memory bridges = new address[](1);
        tokens[0] = USDC_ADDRESS;
        bridges[0] = HOP_USDC_BRIDGE;
        zapDest.setTokenToHopBridge(tokens, bridges);

        // Calculate amount received in withdraw
        vm.roll(block.timestamp);
        bytes1 swapId = 0x01;
        bytes1 bridgeId = 0x02;
        bytes1 dexId = 0x02; // 0x02 for Sushi
        address toToken = USDC_ADDRESS;
        (
            bytes memory srcAddress,
            uint64 nonce,
            bytes memory payload
        ) = _setupSwapAndBridge(
                layerZeroRelayer,
                sender,
                EPOCH_ID,
                bridgeId,
                swapId,
                dexId,
                toToken
            );

        vm.startPrank(layerZeroRelayer);
        vm.expectEmit(true, true, true, false);
        emit ReceivedWithdrawal(0x01, sender, amount); // 0x01 is the funcSelector for withdraw
        zapDest.lzReceive(srcChainId, srcAddress, nonce, payload);

        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(zapDest)), 0);
        assertEq(
            IERC1155(EARTHQUAKE_VAULT).balanceOf(address(zapDest), EPOCH_ID),
            0
        );
    }

    /////////////////////////////////////////
    //                 ERRORS              //
    /////////////////////////////////////////
    function testErrors_ZapDestConstructor() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            address(0),
            layerZeroRelayer,
            EARTHQUAKE_VAULT,
            CELER_BRIDGE,
            HYPHEN_BRIDGE,
            CAMELOT_FACTORY,
            UNISWAP_V3_FACTORY
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            stargateRelayer,
            address(0),
            EARTHQUAKE_VAULT,
            CELER_BRIDGE,
            HYPHEN_BRIDGE,
            CAMELOT_FACTORY,
            UNISWAP_V3_FACTORY
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            stargateRelayer,
            layerZeroRelayer,
            address(0),
            CELER_BRIDGE,
            HYPHEN_BRIDGE,
            CAMELOT_FACTORY,
            UNISWAP_V3_FACTORY
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            stargateRelayer,
            layerZeroRelayer,
            EARTHQUAKE_VAULT,
            address(0),
            HYPHEN_BRIDGE,
            CAMELOT_FACTORY,
            UNISWAP_V3_FACTORY
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            stargateRelayer,
            layerZeroRelayer,
            EARTHQUAKE_VAULT,
            CELER_BRIDGE,
            address(0),
            CAMELOT_FACTORY,
            UNISWAP_V3_FACTORY
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            stargateRelayer,
            layerZeroRelayer,
            EARTHQUAKE_VAULT,
            CELER_BRIDGE,
            HYPHEN_BRIDGE,
            address(0),
            UNISWAP_V3_FACTORY
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            stargateRelayer,
            layerZeroRelayer,
            EARTHQUAKE_VAULT,
            CELER_BRIDGE,
            HYPHEN_BRIDGE,
            CAMELOT_FACTORY,
            address(0)
        );
    }

    function testErrors_trustedRemote() public {
        uint16 srcChainId = 1;
        bytes memory trustedAddress = "";

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);
    }

    function testErrors_sgReceive() public {
        uint16 chainId = 0;
        bytes memory data = "";
        uint256 nonce = 0;
        bytes memory payload = "";

        vm.expectRevert(IErrors.InvalidCaller.selector);
        zapDest.sgReceive(chainId, data, nonce, USDC_ADDRESS, 100, payload);
    }

    function testErrors_lzReceive() public {
        uint16 srcChainId = 0;
        bytes memory srcAddress = "";
        uint64 nonce = 0;
        bytes memory payload = "";

        vm.expectRevert(IErrors.InvalidCaller.selector);
        zapDest.lzReceive(srcChainId, srcAddress, nonce, payload);

        // TODO: Invalid Caller for keccak256
        // TODO: Null Balance
        // TODO: InvalidInput
    }
}
