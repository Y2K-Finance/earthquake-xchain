// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../../test/utils/Helper.sol";
import "../../src/zaps/Y2KGMXZap.sol";
import "../../src/zaps/Y2KCurveZap.sol";
import "../../src/zaps/Y2KUniswapV2Zap.sol";
import "../../src/zaps/Y2KUniswapV3Zap.sol";
import "../../src/zaps/Y2KBalancerZap.sol";
import "../../src/zaps/Y2KCamelotZap.sol";

contract DeployZapScript is Script, Helper {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        Y2KCamelotZap zapCamelot = new Y2KCamelotZap(CAMELOT_FACTORY, PERMIT_2);
        Y2KUniswapV2Zap zapSushiV2 = new Y2KUniswapV2Zap(
            SUSHI_V2_FACTORY,
            PERMIT_2
        );
        Y2KBalancerZap zapBalancer = new Y2KBalancerZap(
            BALANCER_VAULT,
            PERMIT_2
        );
        Y2KUniswapV3Zap zapUniV3 = new Y2KUniswapV3Zap(
            UNISWAP_V3_FACTORY,
            PERMIT_2
        );
        Y2KCurveZap zapCurve = new Y2KCurveZap(WETH_ADDRESS, PERMIT_2);
        Y2KGMXZap zapGMX = new Y2KGMXZap(GMX_VAULT, PERMIT_2);

        vm.stopBroadcast();

        console2.logAddress(address(zapUniV3));
        console2.logAddress(address(zapSushiV2));
        console2.logAddress(address(zapCamelot));
        console2.logAddress(address(zapBalancer));
        console2.logAddress(address(zapCurve));
        console2.logAddress(address(zapGMX));
    }
}
