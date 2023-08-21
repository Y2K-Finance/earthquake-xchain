// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../../test/utils/Helper.sol";
import "../../src/bridgeZaps/zapDest.sol";
import "../../src/bridgeZaps/zapFrom.sol";

// forge script BridgeTestScript --rpc-url $MAINNET_RPC_URL --private-key $PRIVATE_KEY --broadcast --skip-simulation -vv
// forge script BridgeTestScript --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --skip-simulation -vv
// forge script BridgeTestScript --rpc-url $OPTIMISM_RPC_URL --private-key $PRIVATE_KEY --broadcast --skip-simulation -vv
contract BridgeTestScript is Script, Helper {
    address payable zapDestArb =
        payable(0x546355099673a055F3a3aAb7007b9f0F5567832a);
    address payable zapFromEth =
        payable(0x4fEd980114bA926fa8562E2C3E6879F39556088A);
    address payable zapFromOp =
        payable(0x4fEd980114bA926fa8562E2C3E6879F39556088A); // OP w/slice: 0x4fEd980114bA926fa8562E2C3E6879F39556088A | w/o: 0xbc8607Ec58B1C3B027Fa3B2C83C82783Bc7b04Ce
    address receiver = 0x2d244ed7d17AE47886f7f13F53e74b6B0bC16fdC;

    // Vault test info (on Arbitrum)
    address mockVault = 0xb5140DaD4e442849dC47f0854F1f5fd459d5c0d7;
    address usdcVaultV2 = 0x4410ea8E14b07A5f4e873803FEc45FF44934F0f2;
    address usdcVaultV1 = 0x7BB5EE84ba30A8D4CfF259073FbACC6B702bce9D;
    uint256 epochIdV2 =
        258376409407019161791936282549740329323341821142889855677735427933920397154;
    uint256 epochIdV1 = 1688947200;
    address vaultAddress;

    ZapFrom zapFrom;
    ZapDest zapDest;

    function setUp() public {
        zapDest = ZapDest(zapDestArb);
        vaultAddress = mockVault; // Vault to deposit to on bridge
    }

    function run() public {
        uint256 sideToTest = 2; // 1 for zapFrom and 2 for zapDest
        uint256 network = 10; // 1: mainnet, 42161: arbitrum, 10: optimism

        vm.startBroadcast();
        if (sideToTest == 1) _testFrom(network);
        else if (sideToTest == 2) _testDest(network);

        vm.stopBroadcast();
    }

    function _testFrom(uint256 network) internal {
        if (network == 1) _testBridgeEth();
        else if (network == 10) _testBridgeOptimism();
    }

    function _testDest(uint256 network) internal {
        if (network == 10) _testWithdrawOptimism();
    }

    // Bridging tx's //

    function _testBridgeEth() internal {
        zapFrom = ZapFrom(zapFromEth);

        uint256 amountIn = 0.01 ether;
        uint256 amount = 0.005 ether;
        address fromToken = address(0);
        uint16 srcPoolId = 13; // What should this be?
        uint16 dstPoolId = 13; // What should this be?
        uint256 depositType = fromToken == address(0) ? 1 : 2;
        bytes memory payload = abi.encode(
            receiver,
            epochIdV2,
            vaultAddress,
            depositType
        );

        zapFrom.bridge{value: amountIn}(
            amount,
            fromToken,
            srcPoolId,
            dstPoolId,
            payload
        );
    }

    function _testBridgeOptimism() internal {
        zapFrom = ZapFrom(zapFromOp);

        uint256 amountIn = 0.005 ether;
        uint256 amount = 0.00025 ether;
        address fromToken = address(0);
        uint16 srcPoolId = 13; // What should this be?
        uint16 dstPoolId = 13; // What should this be?
        uint256 depositType = fromToken == address(0) ? 1 : 2;
        bytes memory payload = abi.encode(
            receiver,
            epochIdV2,
            vaultAddress,
            depositType
        );

        zapFrom.bridge{value: amountIn}(
            amount,
            fromToken,
            srcPoolId,
            dstPoolId,
            payload
        );
    }

    // Withdrawing tx's //
    function _testWithdrawOptimism() internal {
        zapFrom = ZapFrom(zapFromOp);
        bytes1 funcSelector = 0x01;
        bytes1 bridgeId = 0x00;
        uint256 gasAmount = 0.002 ether;

        bytes memory payload = abi.encode(
            funcSelector,
            bridgeId,
            address(0), // Replaced in the function,
            epochIdV2,
            vaultAddress
        );
        zapFrom.withdraw{value: gasAmount}(payload);
    }
}
