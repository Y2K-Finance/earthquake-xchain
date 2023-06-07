// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";

abstract contract Helper is Test {
    string public MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string public ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");

    ////////////// TOKEEN INFO STATE VARS //////////////
    address constant USDC_ADDRESS = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant USDT_ADDRESS = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant DAI_ADDRESS = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address constant WETH_ADDRESS = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant FRAX_ADDRESS = 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F;
    address constant DUSD_ADDRESS = 0xF0B5cEeFc89684889e5F7e0A7775Bd100FcD3709;
    address constant sender = address(0x01);
    address constant secondSender = address(0x02);
    uint256 constant BASIS_POINTS_DIVISOR = 10000;

    ////////////// DEX & VAULT STATE VARS //////////////
    address constant EARTHQUAKE_VAULT =
        0xb4fbD25A32d21299e356916044D6FbB078016c46;
    address constant EARTHQUAKE_VAULT_USDT =
        0x76b1803530A3608bD5F1e4a8bdaf3007d7d2D7FA;
    address constant EARTHQUAKE_FACTORY =
        0x984E0EB8fB687aFa53fc8B33E12E04967560E092;
    address constant CAMELOT_FACTORY =
        0x6EcCab422D763aC031210895C81787E87B43A652;
    address constant SUSHI_V2_FACTORY =
        0xc35DADB65012eC5796536bD9864eD8773aBc74C4;
    address constant BALANCER_VAULT =
        0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address constant PERMIT_2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    bytes32 constant USDT_USDC_POOL_ID_BALANCER =
        0x1533a3278f3f9141d5f820a184ea4b017fce2382000000000000000000000016;
    bytes32 constant USDC_WETH_POOL_ID_BALANCER =
        0x64541216bafffeec8ea535bb71fbc927831d0595000100000000000000000002;
    bytes32 constant DUSD_DAI_POOL_ID_BALANCER =
        0xd89746affa5483627a87e55713ec1905114394950002000000000000000000bf;
    address constant FRAX_USDC_POOL_CURVE =
        0xC9B8a3FDECB9D5b218d02555a8Baf332E5B740d5;
    address constant USDC_USDT_POOL_CURVE =
        0x7f90122BF0700F9E7e1F688fe926940E8839F353;
    address constant USDT_WETH_POOL_CURVE =
        0x960ea3e3C7FB317332d990873d354E18d7645590;
    address constant CAMELOT_USDC_WETH_PAIR =
        0x84652bb2539513BAf36e225c930Fdd8eaa63CE27;
    address constant SUSHI_USDC_WETH_PAIR =
        0x905dfCD5649217c42684f23958568e533C711Aa3;

    address constant GMX_VAULT = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
    address constant CHRONOS_FACTORY =
        0xCe9240869391928253Ed9cc9Bcb8cb98CB5B0722;
    address constant UNISWAP_V3_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant TJ_LEGACY_FACTORY =
        0x1886D09C9Ade0c5DB822D85D21678Db67B6c2982;
    address constant TJ_FACTORY = 0x8e42f2F4101563bF679975178e880FD87d3eFd4e;
    address constant TJ_FACTORY_V1 = 0xaE4EC9901c3076D0DdBe76A520F9E90a6227aCB7;

    ////////////// EARTHQUAKE VAULT STATE VARS //////////////
    address constant EARTHQUAKE_CONTROLLER =
        0x225aCF1D32f0928A96E49E6110abA1fdf777C85f;
    uint256 constant EPOCH_ID = 1684713600;
    uint256 constant EPOCH_BEGIN = 1684281600;
    uint256 constant EPOCH_ID_USDT = 1684713600;
    uint256 constant EPOCH_BEGIN_USDT = 1684281600;

    //////////////// PERMIT2 VARS ////////////////
    uint256 permitSenderKey = 0x123;
    uint256 permitReceiverKey = 0x456;
    address permitSender;
    address permitReceiver;

    string public constant _PERMIT_TRANSFER_TYPEHASH_STUB =
        "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,";
    string public constant _TOKEN_PERMISSIONS_TYPESTRING =
        "TokenPermissions(address token,uint256 amount)";
    string constant WITNESS_TYPE_STRING =
        "MockWitness witness)MockWitness(uint256 value,address person,bool test)TokenPermissions(address token,uint256 amount)";
    string constant MOCK_WITNESS_TYPE =
        "MockWitness(uint256 value,address person,bool test)";
    bytes32 constant FULL_EXAMPLE_WITNESS_TYPEHASH =
        keccak256(
            "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,MockWitness witness)MockWitness(uint256 value,address person,bool test)TokenPermissions(address token,uint256 amount)"
        );

    ////////////// BRIDGE STATE VARS //////////////
    address constant CELER_BRIDGE = 0x88DCDC47D2f83a99CF0000FDF667A468bB958a78;
    address constant CONNEXT_BRIDGE = address(0x123);
    address constant HYPHEN_BRIDGE = 0x2A5c2568b10A0E826BfA892Cf21BA7218310180b;
}
