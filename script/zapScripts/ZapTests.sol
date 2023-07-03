// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ZapHelper} from "./ZapHelper.sol";
import {Y2KCamelotZap} from "../../src//zaps/Y2KCamelotZap.sol";
import {Y2KUniswapV2Zap} from "../../src//zaps/Y2KUniswapV2Zap.sol";
import {Y2KBalancerZap} from "../../src//zaps/Y2KBalancerZap.sol";
import {Y2KUniswapV3Zap} from "../../src//zaps/Y2KUniswapV3Zap.sol";
import {Y2KCurveZap} from "../../src//zaps/Y2KCurveZap.sol";
import {Y2KGMXZap} from "../../src//zaps/Y2KGMXZap.sol";

// forge script ZapTestScript --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --broadcast
contract ZapTestScript is ZapHelper {
    address usdcVaultV2 = 0x4410ea8E14b07A5f4e873803FEc45FF44934F0f2;
    address usdcVaultV1 = 0x7BB5EE84ba30A8D4CfF259073FbACC6B702bce9D;
    uint256 epochIdV2 =
        258376409407019161791936282549740329323341821142889855677735427933920397154;
    uint256 epochIdV1 = 1688947200;

    function setUp() public {
        address usdcVault = 0x7BB5EE84ba30A8D4CfF259073FbACC6B702bce9D; // NOTE: Change this based on vault
        epochId = epochIdV1; // NOTE: Change this based on vault
        vaultAddress = usdcVaultV1;
        dexId = 3; // NOTE: 1 = Balancer | 2 = Camelot | 3 = Curve | 4 = GMX | 5 = Sushi | 6 = UniV3

        zapBalancer = Y2KBalancerZap(balancerZapper);
        zapCamelot = Y2KCamelotZap(camelotZapper);
        zapCurve = Y2KCurveZap(curveZapper);
        zapGMX = Y2KGMXZap(gmxZapper);
        zapSushiV2 = Y2KUniswapV2Zap(sushiZapper);
        zapUniswapV3 = Y2KUniswapV3Zap(uniswapV3Zapper);
    }

    function run() public {
        vm.startBroadcast();

        if (dexId == 1) _testBalancer();
        else if (dexId == 2) _testCamelot();
        else if (dexId == 3) _testCurve();
        else if (dexId == 4) _testGMX();
        else if (dexId == 5) _testSushi();
        else if (dexId == 6) _testUniV3();

        vm.stopBroadcast();
    }
}
