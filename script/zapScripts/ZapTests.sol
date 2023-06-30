// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ZapHelper} from "./ZapHelper.sol";
import {Y2KCamelotZap} from "../../src//zaps/Y2KCamelotZap.sol";
import {Y2KUniswapV2Zap} from "../../src//zaps/Y2KUniswapV2Zap.sol";
import {Y2KBalancerZap} from "../../src//zaps/Y2KBalancerZap.sol";
import {Y2KUniswapV3Zap} from "../../src//zaps/Y2KUniswapV3Zap.sol";
import {Y2KCurveZap} from "../../src//zaps/Y2KCurveZap.sol";
import {Y2KGMXZap} from "../../src//zaps/Y2KGMXZap.sol";

contract ZapTestScript is ZapHelper {
    function setUp() public {
        address usdcVault = 0x7BB5EE84ba30A8D4CfF259073FbACC6B702bce9D; // NOTE: Change this based on vault
        epochId = 1000; // NOTE: Change this based on vault
        vaultAddress = usdcVault;
        dexId = 1; // NOTE: 1 = Balancer | 2 = Camelot | 3 = Curve | 4 = GMX | 5 = Sushi | 6 = UniV3

        zapCamelot = Y2KCamelotZap(camelotZapper);
        zapBalancer = Y2KBalancerZap(balancerZapper);
        zapGMX = Y2KGMXZap(gmxZapper);
        zapCurve = Y2KCurveZap(curveZapper);
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
