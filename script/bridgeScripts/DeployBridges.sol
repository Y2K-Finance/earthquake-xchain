// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../../test/utils/Helper.sol";
import "../../src/bridgeZaps/zapDest.sol";
import "../../src/bridgeZaps/zapFrom.sol";
import "../../src/bridgeZaps/mock/mockVault.sol";

// forge script DeployLzScript --rpc-url $MAINNET_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --skip-simulation --slow -vv
// forge script DeployLzScript --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --skip-simulation --slow -vv
// forge script DeployLzScript --rpc-url $OPTIMISM_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --skip-simulation --slow -vv
contract DeployLzScript is Script, Helper {
    uint256 network;
    bool deployMockVault;
    address public stargateRelayer = 0xeCc19E177d24551aA7ed6Bc6FE566eCa726CC8a9;

    function setUp() public {
        network = 10; // 1: mainnet, 42161: arbitrum, 10: optimism, 999: null network to deploy vault
        deployMockVault = true;
        y2kArbRouter = 0x546355099673a055F3a3aAb7007b9f0F5567832a;
    }

    function run() public {
        if (network == 0) revert();

        vm.startBroadcast();
        if (network == 1) {
            _deployToMainnet();
        } else if (network == 42161) {
            _deployToArbitrum();
        } else if (network == 10) {
            _deployToOptimism();
        } else if (deployMockVault) {
            _deployMockVault();
        } else {
            revert();
        }

        vm.stopBroadcast();
    }

    function _deployMockVault() internal {
        MockVault mockVault = new MockVault(WETH_ADDRESS);
        console2.logAddress(address(mockVault));
    }

    function _deployToArbitrum() internal {
        ZapDest zapDest = new ZapDest(
            stargateRelayer,
            LAYER_ZERO_ROUTER_REMOTE,
            CELER_BRIDGE,
            HYPHEN_BRIDGE,
            CAMELOT_FACTORY,
            SUSHI_V2_FACTORY,
            UNISWAP_V3_FACTORY,
            SGETH_ADDRESS,
            PRIMARY_INIT_HASH_ARB,
            SECONDARY_INIT_HASH_ARB
        );
        console2.logAddress(address(zapDest));
    }

    function _deployToOptimism() internal {
        address stargateRouterOptimism = 0xB0D502E938ed5f4df2E681fE6E419ff29631d62b;
        // NOTE: LZ chainId is 111 for Optimism
        address layerZeroRouterOptimism = 0x3c2269811836af69497E5F486A85D7316753cf62;
        address uniswapV2ForkFactoryOptimism = 0x7eeaE829DF28f9ce522274d577970dC9FF3e64B2;
        address sushiV2ForkFactory = 0x7eeaE829DF28f9ce522274d577970dC9FF3e64B2;
        address wethAddressOptimism = 0x4200000000000000000000000000000000000006;
        // TODO: Need to change the init hashes being used - uniswapV2 & sushi not on Optimism
        // NOTE: Velodrome may have different implementation on Optimism
        ZapFrom zapFrom = new ZapFrom(
            ZapFrom.Config(
                stargateRouterOptimism,
                layerZeroRouterOptimism,
                y2kArbRouter,
                uniswapV2ForkFactoryOptimism,
                sushiV2ForkFactory,
                UNISWAP_V3_FACTORY,
                BALANCER_VAULT,
                wethAddressOptimism,
                PERMIT_2,
                PRIMARY_INIT_HASH_ETH,
                SECONDARY_INIT_HASH_ETH
            )
        );
        console2.logAddress(address(zapFrom));
    }

    function _deployToMainnet() internal {
        ZapFrom zapFrom = new ZapFrom(
            ZapFrom.Config(
                STARGATE_ROUTER,
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
