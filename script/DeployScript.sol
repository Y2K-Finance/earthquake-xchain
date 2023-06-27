// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../test/utils/Helper.sol";
import "../src/bridgeZaps/zapDest.sol";
import "../src/bridgeZaps/zapFrom.sol";

contract DeployLzScript is Script, Helper {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        // address stargateRelayer = 0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614;
        // address stargateRelayerEth = 0xb1b2eeF380f21747944f46d28f683cD1FBB4d03c;
        // ZapDest zapDest = new ZapDest(
        //     stargateRelayer,
        //     stargateRelayerEth,
        //     LAYER_ZERO_ROUTER_REMOTE,
        //     CELER_BRIDGE,
        //     HYPHEN_BRIDGE,
        //     CAMELOT_FACTORY,
        //     SUSHI_V2_FACTORY,
        //     UNISWAP_V3_FACTORY,
        //     PRIMARY_INIT_HASH_ARB,
        //     SECONDARY_INIT_HASH_ARB
        // );

        address y2kArbRouter = 0x9c668A934611706F84f5B22705eCDF94C3349c5d;
        ZapFrom zapFrom = new ZapFrom(
            ZapFrom.Config(
                STARGATE_ROUTER,
                STARGATE_ROUTER_USINGETH,
                LAYER_ZERO_ROUTER_LOCAL,
                y2kArbRouter,
                UNISWAP_V2_FACTORY,
                SUSHI_V2_FACTORY_ETH,
                UNISWAP_V3_FACTORY,
                BALANCER_VAULT,
                WETH_ADDRESS_ETH,
                PRIMARY_INIT_HASH_ETH,
                SECONDARY_INIT_HASH_ETH
            )
        );

        vm.stopBroadcast();

        // console2.logAddress(address(zapDest));
        console2.logAddress(address(zapFrom));
    }
}
