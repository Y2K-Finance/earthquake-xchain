// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../../test/utils/Helper.sol";
import "../../src/bridgeZaps/zapDest.sol";
import "../../src/bridgeZaps/zapFrom.sol";

// forge script BridgeTestScript --rpc-url $MAINNET_RPC_URL --private-key $PRIVATE_KEY --broadcast --skip-simulation -vv
contract BridgeTestScript is Script, Helper {
    address payable zapDestArb =
        payable(0x1758ED7324718423fC7c4Fc3FC3747eC3861cBdB);
    address payable zapFromEth =
        payable(0x4fEd980114bA926fa8562E2C3E6879F39556088A);
    address receiver = 0x2d244ed7d17AE47886f7f13F53e74b6B0bC16fdC;

    address usdcVaultV2 = 0x4410ea8E14b07A5f4e873803FEc45FF44934F0f2;
    address usdcVaultV1 = 0x7BB5EE84ba30A8D4CfF259073FbACC6B702bce9D;
    uint256 epochIdV2 =
        258376409407019161791936282549740329323341821142889855677735427933920397154;
    uint256 epochIdV1 = 1688947200;
    address vaultAddress;

    ZapFrom zapFrom;
    ZapDest zapDest;

    function setUp() public {
        zapFrom = ZapFrom(zapFromEth);
        zapDest = ZapDest(zapDestArb);
        vaultAddress = usdcVaultV1;
    }

    function run() public {
        uint256 networkToTest = 1; // 1 for Ethereum and 2 for Arbitrum
        vm.startBroadcast();
        if (networkToTest == 1) _testFrom();
        else _testDest();

        vm.stopBroadcast();
    }

    function _testFrom() internal {
        _testBridgeEth();
    }

    function _testDest() internal {}

    function _testBridgeEth() internal {
        uint256 amountIn = 0.01 ether;
        uint256 amount = 0.005 ether;
        address fromToken = address(0);
        uint16 srcPoolId = 13; // What should this be?
        uint16 dstPoolId = 13; // What should this be?
        bytes memory payload = abi.encode(receiver, epochIdV1, vaultAddress);

        zapFrom.bridge{value: amountIn}(
            amount,
            fromToken,
            srcPoolId,
            dstPoolId,
            payload
        );
    }
}
