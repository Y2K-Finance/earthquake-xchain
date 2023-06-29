// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../../test/utils/Helper.sol";
import "../../src/bridgeZaps/zapDest.sol";
import "../../src/bridgeZaps/zapFrom.sol";

contract TestLzScript is Script, Helper {
    address zapDestArb = 0x9c668A934611706F84f5B22705eCDF94C3349c5d;
    address zapFromEth = 0x71dcb9Ad1ddf4476B2F550Bc2a8544bD350CE0DE;
    address receiver = 0x2d244ed7d17AE47886f7f13F53e74b6B0bC16fdC;
    uint256 epochId = 1688342400;
    address vaultAddress;
    ZapFrom zapFrom;
    ZapDest zapDest;

    function setUp() public {
        address usdcVault = 0x7BB5EE84ba30A8D4CfF259073FbACC6B702bce9D; // Change this when needed
        zapFrom = ZapFrom(payable(zapFromEth));
        zapDest = ZapDest(zapDestArb);
        vaultAddress = usdcVault;
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
        bytes memory payload = abi.encode(receiver, epochId, vaultAddress);

        zapFrom.bridge{value: amountIn}(
            amount,
            fromToken,
            srcPoolId,
            dstPoolId,
            payload
        );
    }
}
