// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {BridgeHelper} from "../utils/BridgeUtils.sol";
import {ZapDest} from "../../src/bridgeZaps/zapDest.sol";
import {IErrors} from "../../src/interfaces/IErrors.sol";
import {IEarthQuakeVault, IERC1155} from "../utils/Interfaces.sol";

contract BridgeDestTests is BridgeHelper {
    /////////////////////////////////////////
    //               CONFIG                //
    /////////////////////////////////////////
    function forkAndConfig() public {
        assertEq(vm.activeFork(), arbitrumFork);
    }

    /////////////////////////////////////////
    //               STATE VARS            //
    /////////////////////////////////////////
    function test_stateVars() public {
        assertEq(zapDest.STARGATE_RELAYER(), stargateRelayer);
        assertEq(zapDest.LAYER_ZERO_ENDPOINT(), layerZeroRelayer);
        assertEq(address(zapDest.EARTHQUAKE_VAULT()), EARTHQUAKE_VAULT);
        assertEq(address(zapDest.CELER_BRIDGE()), CELER_BRIDGE);
        assertEq(address(zapDest.HYPHEN_BRIDGE()), HYPHEN_BRIDGE);
        assertEq(address(zapDest.CONNEXT_BRIDGE()), CONNEXT_BRIDGE);
    }

    /////////////////////////////////////////
    //              VAULT FUNCTIONS        //
    /////////////////////////////////////////
    function test_depositVault() public {
        address token = WETH_ADDRESS;
        (
            bytes memory srcAddress,
            uint64 nonce,
            uint256 amount,
            bytes memory payload
        ) = setupSgReceiveDeposit(stargateRelayer, sender, token, EPOCH_ID);

        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        vm.prank(stargateRelayer);
        zapDest.sgReceive(
            uint16(chainId),
            srcAddress,
            nonce,
            token,
            amount,
            payload
        );
        assertEq(IERC20(WETH_ADDRESS).balanceOf(stargateRelayer), 0);
        assertGe(
            IERC1155(EARTHQUAKE_VAULT).balanceOf(stargateRelayer, EPOCH_ID),
            1
        );
    }

    function _depositToVault() internal returns (uint256) {
        address token = WETH_ADDRESS;
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        (
            bytes memory srcAddress,
            uint64 nonce,
            uint256 amount,
            bytes memory payload
        ) = setupSgReceiveDeposit(stargateRelayer, sender, token, EPOCH_ID);
        vm.prank(stargateRelayer);
        zapDest.sgReceive(
            uint16(chainId),
            srcAddress,
            nonce,
            token,
            amount,
            payload
        );
        assertEq(IERC20(WETH_ADDRESS).balanceOf(stargateRelayer), 0);
        assertGe(
            IERC1155(EARTHQUAKE_VAULT).balanceOf(stargateRelayer, EPOCH_ID),
            1
        );
        return amount;
    }

    function setupLzReceiveWithdraw(
        address sender,
        address receiver.
        uint256 epochId
    )
        internal
        returns (bytes memory srcAddress, uint64 nonce, bytes memory payload)
    {
        srcAddress = abi.encode(sender);
        nonce = 0;
        bytes1 funcSelector = 0x01;
        bytes1 bridgeId = 0x00;

        payload = abi.encode(funcSelector, bridgeId, receiver, epochId);
    }

    function test_withdrawVault() public {
        uint256 amount = _depositToVault();
        address receiver = secondSender;
        uint16 srcChainId = 1;

        // Setting this to sender for testing purposes - should be contract addr on srcChain
        bytes memory trustedAddress = abi.encode(sender);
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);

        // Ending the vault
        

        (
            bytes memory srcAddress,
            uint64 nonce,
            bytes memory payload
        ) = setupLzReceiveWithdraw(sender, receiver, EPOCH_ID);
        zapDest.lzReceive(srcChainId, _srcAddress, _nonce, _payload);

        assertEq(IERC20(WETH_ADDRESS).balanceOf(stargateRelayer), 0);
        asserteq(IERC20(WETH_ADDRESS).balanceOf(receiver), amount);
    }

    /////////////////////////////////////////
    //              BRIDGE FUNCTIONS       //
    /////////////////////////////////////////
    function test_withdrawAndBridgeWithHyphen() public {}

    function test_withdrawAndBridgeWithCeler() public {}

    function test_withdrawAndBridgeWithConnext() public {}

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
            CONNEXT_BRIDGE
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            stargateRelayer,
            address(0),
            EARTHQUAKE_VAULT,
            CELER_BRIDGE,
            HYPHEN_BRIDGE,
            CONNEXT_BRIDGE
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            stargateRelayer,
            layerZeroRelayer,
            address(0),
            CELER_BRIDGE,
            HYPHEN_BRIDGE,
            CONNEXT_BRIDGE
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            stargateRelayer,
            layerZeroRelayer,
            EARTHQUAKE_VAULT,
            address(0),
            HYPHEN_BRIDGE,
            CONNEXT_BRIDGE
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            stargateRelayer,
            layerZeroRelayer,
            EARTHQUAKE_VAULT,
            CELER_BRIDGE,
            address(0),
            CONNEXT_BRIDGE
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            stargateRelayer,
            layerZeroRelayer,
            EARTHQUAKE_VAULT,
            CELER_BRIDGE,
            HYPHEN_BRIDGE,
            address(0)
        );
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
