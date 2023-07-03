// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../../test/utils/Helper.sol";
import "../../src/bridgeZaps/zapDest.sol";
import "../../src/bridgeZaps/zapFrom.sol";

// forge script DeployLzScript --rpc-url $MAINNET_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --skip-simulation --slow -vv
// forge script DeployLzScript --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --skip-simulation --slow -vv
contract DeployLzScript is Script, Helper {
    uint256 network;

    function setUp() public {
        network = 1; // 1 for Ethereum and 2 for Arbitrum
    }

    function run() public {
        if (network == 0) revert();

        vm.startBroadcast();
        if (network == 1) {
            _deployToMainnet();
        } else {
            _deployToArbitrum();
        }

        vm.stopBroadcast();
    }

    function _deployToArbitrum() internal {
        address stargateRelayer = 0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614;
        address stargateRelayerEth = 0xb1b2eeF380f21747944f46d28f683cD1FBB4d03c;
        ZapDest zapDest = new ZapDest(
            stargateRelayer,
            stargateRelayerEth,
            LAYER_ZERO_ROUTER_REMOTE,
            CELER_BRIDGE,
            HYPHEN_BRIDGE,
            CAMELOT_FACTORY,
            SUSHI_V2_FACTORY,
            UNISWAP_V3_FACTORY,
            PRIMARY_INIT_HASH_ARB,
            SECONDARY_INIT_HASH_ARB
        );
        console2.logAddress(address(zapDest));
    }

    function _deployToMainnet() internal {
        address y2kArbRouter = 0x1758ED7324718423fC7c4Fc3FC3747eC3861cBdB;
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
                PERMIT_2,
                PRIMARY_INIT_HASH_ETH,
                SECONDARY_INIT_HASH_ETH
            )
        );
        console2.logAddress(address(zapFrom));
    }
}
