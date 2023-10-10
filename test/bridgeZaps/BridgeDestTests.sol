// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "forge-std/Test.sol";
import {BridgeHelper} from "../utils/BridgeUtils.sol";
import {ZapDest} from "../../src/bridgeZaps/zapDest.sol";
import {IErrors} from "../../src/interfaces/IErrors.sol";
import {BytesLib} from "../../src/libraries/BytesLib.sol";
import {IEarthQuakeVault, IERC1155, IEarthquakeController} from "../utils/Interfaces.sol";

contract BridgeDestTests is BridgeHelper {
    using BytesLib for bytes;

    /////////////////////////////////////////
    //               CONFIG                //
    /////////////////////////////////////////
    function setUp() public {
        setUpArbitrum();
    }

    function test_forkDest() public {
        assertEq(vm.activeFork(), arbitrumFork);
        assertEq(
            IEarthQuakeVault(EARTHQUAKE_VAULT).controller(),
            EARTHQUAKE_CONTROLLER
        );
    }

    /////////////////////////////////////////
    //               STATE VARS            //
    /////////////////////////////////////////
    function test_stateVarsDest() public {
        assertEq(zapDest.stargateRelayer(), stargateRelayer);
        assertEq(zapDest.layerZeroEndpoint(), layerZeroEndpoint);
        assertEq(address(zapDest.celerBridge()), CELER_BRIDGE);
        assertEq(address(zapDest.hyphenBridge()), HYPHEN_BRIDGE);
        assertEq(zapDest.uniswapV2ForkFactory(), CAMELOT_FACTORY);
        assertEq(zapDest.sushiFactory(), SUSHI_V2_FACTORY);
        assertEq(zapDest.uniswapV3Factory(), UNISWAP_V3_FACTORY);
    }

    /////////////////////////////////////////
    //       STATE CHANGING FUNCTIONS       //
    /////////////////////////////////////////
    function test_setTrustedRemoteLookup() public {
        uint16 srcChainId = 1;
        bytes memory trustedAddress = abi.encode(layerZeroEndpoint);

        vm.expectEmit(true, true, true, false);
        emit TrustedRemoteAdded(srcChainId, trustedAddress, address(this));
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);

        assertEq(zapDest.trustedRemoteLookup(srcChainId), trustedAddress);
    }

    function test_setTokenToHopBridge() public {
        address[] memory tokens = new address[](2);
        tokens[0] = USDC_ADDRESS;
        tokens[1] = USDT_ADDRESS;

        address[] memory bridges = new address[](2);
        bridges[0] = HOP_USDC_BRIDGE;
        bridges[1] = HOP_USDT_BRIDGE;

        vm.expectEmit(true, true, true, false);
        emit TokenToHopBridgeSet(tokens, bridges, address(this));
        zapDest.setTokenToHopBridge(tokens, bridges);

        assertEq(zapDest.tokenToHopBridge(USDC_ADDRESS), HOP_USDC_BRIDGE);
        assertEq(zapDest.tokenToHopBridge(USDT_ADDRESS), HOP_USDT_BRIDGE);
    }

    function test_whitelistVault() public {
        vm.expectEmit(true, true, true, false);
        emit VaultWhitelisted(EARTHQUAKE_VAULT_USDT, address(this));
        zapDest.whitelistVault(EARTHQUAKE_VAULT_USDT);

        assertEq(zapDest.whitelistedVault(EARTHQUAKE_VAULT_USDT), 1);
    }

    /////////////////////////////////////////
    //        VAULT PUBLIC FUNCTIONS        //
    /////////////////////////////////////////

    function test_depositWithSgReceive() public {
        address token = WETH_ADDRESS;
        (
            bytes memory srcAddress,
            uint64 nonce,
            uint256 amount,
            bytes memory payload,
            uint256 chainId
        ) = setupSgReceiveDeposit(
                stargateRelayer,
                sender,
                token,
                EPOCH_ID,
                EARTHQUAKE_VAULT
            );

        vm.startPrank(stargateRelayer);
        vm.expectEmit(true, true, true, false);
        emit ReceivedDeposit(token, address(zapDest), amount);
        zapDest.sgReceive(
            uint16(chainId),
            srcAddress,
            nonce,
            token,
            amount,
            payload
        );

        assertEq(
            zapDest.receiverToVaultToIdToAmount(
                sender,
                EARTHQUAKE_VAULT,
                EPOCH_ID
            ),
            amount
        );
        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(zapDest)), 0);
        assertGe(
            IERC1155(EARTHQUAKE_VAULT).balanceOf(address(zapDest), EPOCH_ID),
            1
        );
    }

    function test_depositEthWithSgReceive() public {
        address token = WETH_ADDRESS;
        (
            bytes memory srcAddress,
            uint64 nonce,
            ,
            bytes memory payload,
            uint256 chainId
        ) = setupSgReceiveDeposit(
                stargateRelayer,
                sender,
                token,
                EPOCH_ID,
                EARTHQUAKE_VAULT
            );
        // NOTE: Overwriting for ETH
        uint256 amount = 1e17;
        token = address(0);

        vm.startPrank(stargateRelayer);
        vm.expectEmit(true, true, true, false);

        vm.deal(stargateRelayer, amount);
        assertGe(stargateRelayer.balance, amount);

        emit ReceivedDeposit(token, address(zapDest), amount);
        zapDest.sgReceive{value: amount}(
            uint16(chainId),
            srcAddress,
            nonce,
            SGETH_ADDRESS, // NOTE: SGETH used to recognise ETH deposits
            amount,
            payload
        );

        assertEq(
            zapDest.receiverToVaultToIdToAmount(
                sender,
                EARTHQUAKE_VAULT,
                EPOCH_ID
            ),
            amount
        );
        assertEq(address(zapDest).balance, 0);
        assertGe(
            IERC1155(EARTHQUAKE_VAULT).balanceOf(address(zapDest), EPOCH_ID),
            1
        );
    }

    function test_withdrawWithLzReceive() public {
        // Deposits to the valut as the sender
        uint256 amount = _depositToVault(sender, EARTHQUAKE_VAULT);
        uint16 srcChainId = 1;

        // Set the trusted remote
        bytes memory trustedAddress = abi.encode(layerZeroEndpoint);
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);

        // Calculate amount received in withdraw
        vm.roll(block.timestamp);
        uint256 amountOut = (IEarthQuakeVault(EARTHQUAKE_VAULT).previewWithdraw(
            EPOCH_ID,
            amount
        ) * 99) / 100;

        // Withdraw from vault
        (
            bytes memory srcAddress,
            uint64 nonce,
            bytes memory payload
        ) = _setupLzReceiveWithdraw(
                layerZeroEndpoint,
                sender,
                EPOCH_ID,
                EARTHQUAKE_VAULT
            );
        vm.startPrank(layerZeroEndpoint);
        vm.expectEmit(true, true, true, false);
        emit ReceivedWithdrawal(0x01, sender, amount); // 0x01 is the funcSelector for withdraw
        zapDest.lzReceive(srcChainId, srcAddress, nonce, payload);

        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(zapDest)), 0);
        assertGe(IERC20(WETH_ADDRESS).balanceOf(sender), amountOut);
        assertEq(
            IERC1155(EARTHQUAKE_VAULT).balanceOf(address(zapDest), EPOCH_ID),
            0
        );
    }

    function test_withdrawOnDest() public {
        // Deposits to the valut as the sender
        uint256 amount = _depositToVault(sender, EARTHQUAKE_VAULT);
        bytes1 funcSelector = 0x01;
        bytes1 bridgeId = 0x00;
        uint16 srcChainId = 1;

        // Calculate amount received in withdraw
        vm.roll(block.timestamp);
        uint256 amountOut = (IEarthQuakeVault(EARTHQUAKE_VAULT).previewWithdraw(
            EPOCH_ID,
            amount
        ) * 99) / 100;

        // Withdraw from vault
        vm.startPrank(sender);
        vm.expectEmit(true, true, true, false);
        emit ReceivedWithdrawal(0x01, sender, amount); // 0x01 is the funcSelector for withdraw
        zapDest.withdraw(
            funcSelector,
            bridgeId,
            sender,
            EPOCH_ID,
            srcChainId,
            EARTHQUAKE_VAULT,
            bytes("")
        );

        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(zapDest)), 0);
        assertGe(IERC20(WETH_ADDRESS).balanceOf(sender), amountOut);
    }

    function testWithdrawRefundERC20() public {
        uint16 chainId = 0;
        bytes memory data = "";
        uint256 nonce = 0;
        bytes memory payload = abi.encode(sender, 0, EARTHQUAKE_VAULT_USDT);

        uint256 amount = 10e6;
        deal(USDC_ADDRESS, sender, amount);
        uint256 balance = IERC20(USDC_ADDRESS).balanceOf(sender);

        vm.prank(sender);
        IERC20(USDC_ADDRESS).transfer(address(zapDest), amount);

        vm.startPrank(stargateRelayer);

        vm.expectEmit(true, true, true, false);
        emit RefundStaged(sender, USDC_ADDRESS, amount);
        zapDest.sgReceive(chainId, data, nonce, USDC_ADDRESS, amount, payload);
        assertEq(zapDest.eligibleRefund(sender, USDC_ADDRESS), amount);
        vm.stopPrank();

        vm.expectEmit(true, true, true, false);
        emit RefundClaimed(sender, USDC_ADDRESS, amount);
        zapDest.claimRefund(USDC_ADDRESS, sender);

        assertEq(zapDest.eligibleRefund(sender, USDC_ADDRESS), 0);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), balance);
    }

    function testWithdrawRefundEth() public {
        uint16 chainId = 0;
        bytes memory data = "";
        uint256 nonce = 0;
        bytes memory payload = abi.encode(sender, 0, EARTHQUAKE_VAULT_USDT);

        uint256 amount = 1e18;
        vm.deal(sender, amount);
        uint256 balance = sender.balance;

        vm.prank(sender);
        payable(address(zapDest)).transfer(amount);

        vm.startPrank(stargateRelayer);
        zapDest.sgReceive(chainId, data, nonce, SGETH_ADDRESS, amount, payload);
        assertEq(zapDest.eligibleRefund(sender, SGETH_ADDRESS), amount);
        vm.stopPrank();

        vm.expectEmit(true, true, true, false);
        emit RefundClaimed(sender, USDC_ADDRESS, amount);
        zapDest.claimRefund(SGETH_ADDRESS, sender);

        assertEq(zapDest.eligibleRefund(sender, SGETH_ADDRESS), 0);
        assertEq(sender.balance, balance);
    }

    /////////////////////////////////////////
    //              BRIDGE FUNCTIONS       //
    /////////////////////////////////////////
    function test_withdrawAndBridgeWithCeler() public {
        // Deposits to the valut as the sender
        _depositToVault(sender, EARTHQUAKE_VAULT);
        bytes1 funcSelector = 0x02;
        bytes1 bridgeId = 0x01;
        uint16 srcChainId = 1;
        bytes memory payload = abi.encode(1e6);

        // Withdraw from vault
        vm.roll(block.timestamp);
        vm.startPrank(sender);
        zapDest.withdraw(
            funcSelector,
            bridgeId,
            sender,
            EPOCH_ID,
            srcChainId,
            EARTHQUAKE_VAULT,
            payload
        );

        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(zapDest)), 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(sender), 0);
        assertEq(
            IERC1155(EARTHQUAKE_VAULT).balanceOf(address(zapDest), EPOCH_ID),
            0
        );
    }

    /////////////////////////////////////////
    //       BRIDGE & SWAP FUNCTIONS       //
    /////////////////////////////////////////

    /////////////////////////////////////////
    //                HYPHEN                //
    /////////////////////////////////////////
    function test_withdrawSwapCamelotBridgeHyphen() public {
        // Deposits to the valut as the sender
        uint256 amount = _depositToVault(sender, EARTHQUAKE_VAULT);
        uint16 srcChainId = 1;

        // Set the trusted remote
        bytes memory trustedAddress = abi.encode(layerZeroEndpoint);
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);

        // Calculate amount received in withdraw
        vm.roll(block.timestamp);
        bytes1 swapId = 0x01;
        bytes1 bridgeId = 0x02;
        bytes1 dexId = 0x01;
        address toToken = USDC_ADDRESS;

        (
            bytes memory srcAddress,
            uint64 nonce,
            bytes memory payload
        ) = _setupSwapV2AndBridge(
                layerZeroEndpoint,
                sender,
                EPOCH_ID,
                EARTHQUAKE_VAULT,
                bridgeId,
                swapId,
                dexId,
                toToken
            );

        // Payload outputs: (1) bytes1 funcSelector: 0x03, (2) bytes1 bridgeId: 0x01, (3) address receiver: address(0x01)
        // (4) uint256 epochId: 1684713600, (5) bytes1 swapId: 0x01, (6) uint256 toAmountMin: 10e8, (7) bytes1 dexId: 0x01
        vm.startPrank(layerZeroEndpoint);
        vm.expectEmit(true, true, true, false);
        emit ReceivedWithdrawal(0x01, sender, amount); // 0x01 is the funcSelector for withdraw
        zapDest.lzReceive(srcChainId, srcAddress, nonce, payload);

        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(zapDest)), 0);
        assertEq(
            IERC1155(EARTHQUAKE_VAULT).balanceOf(address(zapDest), EPOCH_ID),
            0
        );
    }

    function test_withdrawSwapSushiBridgeHyphen() public {
        // Deposits to the valut as the sender
        uint256 amount = _depositToVault(sender, EARTHQUAKE_VAULT);
        uint16 srcChainId = 1;

        // Set the trusted remote
        bytes memory trustedAddress = abi.encode(layerZeroEndpoint);
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);

        // Calculate amount received in withdraw
        vm.roll(block.timestamp);
        bytes1 swapId = 0x01;
        bytes1 bridgeId = 0x02;
        bytes1 dexId = 0x02;
        address toToken = USDC_ADDRESS;

        (
            bytes memory srcAddress,
            uint64 nonce,
            bytes memory payload
        ) = _setupSwapV2AndBridge(
                layerZeroEndpoint,
                sender,
                EPOCH_ID,
                EARTHQUAKE_VAULT,
                bridgeId,
                swapId,
                dexId,
                toToken
            );

        vm.startPrank(layerZeroEndpoint);
        vm.expectEmit(true, true, true, false);
        emit ReceivedWithdrawal(0x01, sender, amount); // 0x01 is the funcSelector for withdraw
        zapDest.lzReceive(srcChainId, srcAddress, nonce, payload);

        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(zapDest)), 0);
        assertEq(
            IERC1155(EARTHQUAKE_VAULT).balanceOf(address(zapDest), EPOCH_ID),
            0
        );
    }

    function test_withdrawSwapUniV3BridgeHyphen() public {
        // Deposits to the valut as the sender
        uint256 amount = _depositToVault(sender, EARTHQUAKE_VAULT);
        uint16 srcChainId = 1;

        // Set the trusted remote
        bytes memory trustedAddress = abi.encode(layerZeroEndpoint);
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);

        // Calculate amount received in withdraw
        vm.roll(block.timestamp);
        bytes1 swapId = 0x02;
        bytes1 bridgeId = 0x02;
        bytes1 dexId = 0x02;
        address toToken = USDC_ADDRESS;

        (
            bytes memory srcAddress,
            uint64 nonce,
            bytes memory payload
        ) = _setupSwapV3AndBridge(
                layerZeroEndpoint,
                sender,
                EPOCH_ID,
                EARTHQUAKE_VAULT,
                bridgeId,
                swapId,
                dexId,
                toToken
            );

        vm.startPrank(layerZeroEndpoint);
        vm.expectEmit(true, true, true, false);
        emit ReceivedWithdrawal(0x01, sender, amount); // 0x01 is the funcSelector for withdraw
        zapDest.lzReceive(srcChainId, srcAddress, nonce, payload);

        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(zapDest)), 0);
        assertEq(
            IERC1155(EARTHQUAKE_VAULT).balanceOf(address(zapDest), EPOCH_ID),
            0
        );
    }

    /////////////////////////////////////////
    //                HOP                  //
    ////////////////////////////////////////

    function test_withdrawSwapCamelotBridgeHop() public {
        // Deposits to the valut as the sender
        uint256 amount = _depositToVault(sender, EARTHQUAKE_VAULT);
        uint16 srcChainId = 1;

        // Set the trusted remote
        bytes memory trustedAddress = abi.encode(layerZeroEndpoint);
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);

        // Set up bridge info
        _setupHopBridge(USDC_ADDRESS, HOP_USDC_BRIDGE);

        // Calculate amount received in withdraw
        vm.roll(block.timestamp);
        bytes1 swapId = 0x01;
        bytes1 bridgeId = 0x03;
        bytes1 dexId = 0x01; // 0x02 for Sushi
        (
            bytes memory srcAddress,
            uint64 nonce,
            bytes memory payload
        ) = _setupSwapV2AndBridge(
                layerZeroEndpoint,
                sender,
                EPOCH_ID,
                EARTHQUAKE_VAULT,
                bridgeId,
                swapId,
                dexId,
                USDC_ADDRESS // toToken
            );

        vm.startPrank(layerZeroEndpoint);
        vm.expectEmit(true, true, true, false);
        emit ReceivedWithdrawal(0x01, sender, amount); // 0x01 is the funcSelector for withdraw
        zapDest.lzReceive(srcChainId, srcAddress, nonce, payload);

        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(zapDest)), 0);
        assertEq(
            IERC1155(EARTHQUAKE_VAULT).balanceOf(address(zapDest), EPOCH_ID),
            0
        );
    }

    // NOTE: Tests with hop using USDT bridge instead of USDC
    function test_withdrawSwapSushiBridgeHop() public {
        // Deposits to the valut as the sender
        uint256 amount = _depositToVault(sender, EARTHQUAKE_VAULT);
        uint16 srcChainId = 1;

        // Set the trusted remote
        bytes memory trustedAddress = abi.encode(layerZeroEndpoint);
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);

        // Set the hop bridge
        _setupHopBridge(USDT_ADDRESS, HOP_USDT_BRIDGE);

        // Calculate amount received in withdraw
        vm.roll(block.timestamp);
        bytes1 swapId = 0x01;
        bytes1 bridgeId = 0x03;
        bytes1 dexId = 0x02; // 0x02 for Sushi
        (
            bytes memory srcAddress,
            uint64 nonce,
            bytes memory payload
        ) = _setupSwapV2AndBridge(
                layerZeroEndpoint,
                sender,
                EPOCH_ID,
                EARTHQUAKE_VAULT,
                bridgeId,
                swapId,
                dexId,
                USDT_ADDRESS // toToken
            );

        vm.startPrank(layerZeroEndpoint);
        vm.expectEmit(true, true, true, false);
        emit ReceivedWithdrawal(0x01, sender, amount); // 0x01 is the funcSelector for withdraw
        zapDest.lzReceive(srcChainId, srcAddress, nonce, payload);

        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(zapDest)), 0);
        assertEq(
            IERC1155(EARTHQUAKE_VAULT).balanceOf(address(zapDest), EPOCH_ID),
            0
        );
    }

    function test_withdrawSwapUniV3BridgeHop() public {
        // Deposits to the valut as the sender
        uint256 amount = _depositToVault(sender, EARTHQUAKE_VAULT);
        uint16 srcChainId = 1;

        // Set the trusted remote
        bytes memory trustedAddress = abi.encode(layerZeroEndpoint);
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);

        // Set the hop bridge
        _setupHopBridge(USDC_ADDRESS, HOP_USDC_BRIDGE);

        // Calculate amount received in withdraw
        vm.roll(block.timestamp);
        bytes1 swapId = 0x02;
        bytes1 bridgeId = 0x03;
        bytes1 dexId = 0x02; // 0x02 for Sushi
        (
            bytes memory srcAddress,
            uint64 nonce,
            bytes memory payload
        ) = _setupSwapV3AndBridge(
                layerZeroEndpoint,
                sender,
                EPOCH_ID,
                EARTHQUAKE_VAULT,
                bridgeId,
                swapId,
                dexId,
                USDC_ADDRESS // toToken
            );

        vm.startPrank(layerZeroEndpoint);
        vm.expectEmit(true, true, true, false);
        emit ReceivedWithdrawal(0x01, sender, amount); // 0x01 is the funcSelector for withdraw
        zapDest.lzReceive(srcChainId, srcAddress, nonce, payload);

        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(zapDest)), 0);
        assertEq(
            IERC1155(EARTHQUAKE_VAULT).balanceOf(address(zapDest), EPOCH_ID),
            0
        );
    }

    /////////////////////////////////////////
    //                 ERRORS              //
    /////////////////////////////////////////
    function testErrors_ZapDestConstructor() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            address(0),
            layerZeroEndpoint,
            CELER_BRIDGE,
            HYPHEN_BRIDGE,
            CAMELOT_FACTORY,
            SUSHI_V2_FACTORY,
            UNISWAP_V3_FACTORY,
            SGETH_ADDRESS,
            PRIMARY_INIT_HASH_ARB,
            SECONDARY_INIT_HASH_ARB
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            stargateRelayer,
            address(0),
            CELER_BRIDGE,
            HYPHEN_BRIDGE,
            CAMELOT_FACTORY,
            SUSHI_V2_FACTORY,
            UNISWAP_V3_FACTORY,
            SGETH_ADDRESS,
            PRIMARY_INIT_HASH_ARB,
            SECONDARY_INIT_HASH_ARB
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            stargateRelayer,
            layerZeroEndpoint,
            address(0),
            HYPHEN_BRIDGE,
            CAMELOT_FACTORY,
            SUSHI_V2_FACTORY,
            UNISWAP_V3_FACTORY,
            SGETH_ADDRESS,
            PRIMARY_INIT_HASH_ARB,
            SECONDARY_INIT_HASH_ARB
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            stargateRelayer,
            layerZeroEndpoint,
            CELER_BRIDGE,
            address(0),
            CAMELOT_FACTORY,
            SUSHI_V2_FACTORY,
            UNISWAP_V3_FACTORY,
            SGETH_ADDRESS,
            PRIMARY_INIT_HASH_ARB,
            SECONDARY_INIT_HASH_ARB
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            stargateRelayer,
            layerZeroEndpoint,
            CELER_BRIDGE,
            HYPHEN_BRIDGE,
            address(0),
            SUSHI_V2_FACTORY,
            UNISWAP_V3_FACTORY,
            SGETH_ADDRESS,
            PRIMARY_INIT_HASH_ARB,
            SECONDARY_INIT_HASH_ARB
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            stargateRelayer,
            layerZeroEndpoint,
            CELER_BRIDGE,
            HYPHEN_BRIDGE,
            CAMELOT_FACTORY,
            address(0),
            UNISWAP_V3_FACTORY,
            SGETH_ADDRESS,
            PRIMARY_INIT_HASH_ARB,
            SECONDARY_INIT_HASH_ARB
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            stargateRelayer,
            layerZeroEndpoint,
            CELER_BRIDGE,
            HYPHEN_BRIDGE,
            CAMELOT_FACTORY,
            SUSHI_V2_FACTORY,
            address(0),
            SGETH_ADDRESS,
            PRIMARY_INIT_HASH_ARB,
            SECONDARY_INIT_HASH_ARB
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            stargateRelayer,
            layerZeroEndpoint,
            CELER_BRIDGE,
            HYPHEN_BRIDGE,
            CAMELOT_FACTORY,
            SUSHI_V2_FACTORY,
            UNISWAP_V3_FACTORY,
            address(0),
            PRIMARY_INIT_HASH_ARB,
            SECONDARY_INIT_HASH_ARB
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            stargateRelayer,
            layerZeroEndpoint,
            CELER_BRIDGE,
            HYPHEN_BRIDGE,
            CAMELOT_FACTORY,
            SUSHI_V2_FACTORY,
            UNISWAP_V3_FACTORY,
            SGETH_ADDRESS,
            bytes(""),
            SECONDARY_INIT_HASH_ARB
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new ZapDest(
            stargateRelayer,
            layerZeroEndpoint,
            CELER_BRIDGE,
            HYPHEN_BRIDGE,
            CAMELOT_FACTORY,
            SUSHI_V2_FACTORY,
            UNISWAP_V3_FACTORY,
            SGETH_ADDRESS,
            PRIMARY_INIT_HASH_ARB,
            bytes("")
        );
    }

    function testErrors_trustedRemote() public {
        uint16 srcChainId = 1;
        bytes memory trustedAddress = "";

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);
    }

    function testErrors_setTokenHop() public {
        address[] memory tokens = new address[](1);
        tokens[0] = USDC_ADDRESS;

        address[] memory bridges = new address[](2);
        bridges[0] = HOP_USDC_BRIDGE;
        bridges[1] = HOP_USDT_BRIDGE;

        vm.expectRevert(IErrors.InvalidInput.selector);
        zapDest.setTokenToHopBridge(tokens, bridges);
    }

    function testErrors_sgReceiveInvalidCaller() public {
        uint16 chainId = 0;
        bytes memory data = "";
        uint256 nonce = 0;
        bytes memory payload = "";

        vm.expectRevert(IErrors.InvalidCaller.selector);
        zapDest.sgReceive(chainId, data, nonce, USDC_ADDRESS, 100, payload);
    }

    function testErrors_sgReceiveInvalidEpochId() public {
        uint16 chainId = 0;
        bytes memory data = "";
        uint256 nonce = 0;
        bytes memory payload = abi.encode(sender, 0, EARTHQUAKE_VAULT_USDT);

        vm.startPrank(stargateRelayer);
        zapDest.sgReceive(chainId, data, nonce, USDC_ADDRESS, 100, payload);
        assertEq(zapDest.eligibleRefund(sender, USDC_ADDRESS), 100);

        zapDest.sgReceive(chainId, data, nonce, USDC_ADDRESS, 100, payload);
        assertEq(zapDest.eligibleRefund(sender, USDC_ADDRESS), 200);
        vm.stopPrank();
    }

    function testErrors_sgReceiveInvalidVault() public {
        uint16 chainId = 0;
        bytes memory data = "";
        uint256 nonce = 0;
        bytes memory payload = abi.encode(
            sender,
            EPOCH_ID,
            EARTHQUAKE_VAULT_USDT
        );

        vm.startPrank(stargateRelayer);
        zapDest.sgReceive(chainId, data, nonce, USDC_ADDRESS, 100, payload);
        assertEq(zapDest.eligibleRefund(sender, USDC_ADDRESS), 100);
        assertEq(
            zapDest.receiverToVaultToIdToAmount(
                sender,
                EARTHQUAKE_VAULT_USDT,
                EPOCH_ID
            ),
            0
        );

        zapDest.sgReceive(chainId, data, nonce, USDC_ADDRESS, 100, payload);
        assertEq(zapDest.eligibleRefund(sender, USDC_ADDRESS), 200);
        assertEq(
            zapDest.receiverToVaultToIdToAmount(
                sender,
                EARTHQUAKE_VAULT_USDT,
                EPOCH_ID
            ),
            0
        );
        vm.stopPrank();
    }

    function testErrors_ineligibleRefund() public {
        vm.expectRevert(IErrors.IneligibleRefund.selector);
        zapDest.claimRefund(USDC_ADDRESS, sender);
    }

    function testErrors_lzReceiveInvalidCallerSender() public {
        uint16 srcChainId = 1;
        bytes memory srcAddress = abi.encode(sender);
        uint64 nonce = 0;
        bytes memory payload = "";

        vm.expectRevert(IErrors.InvalidCaller.selector);
        zapDest.lzReceive(srcChainId, srcAddress, nonce, payload);
    }

    function testErrors_lzReceiveInvalidLength() public {
        uint16 srcChainId = 1;
        bytes memory srcAddress = abi.encode(sender);
        uint64 nonce = 0;
        bytes memory payload = "";

        vm.startPrank(layerZeroEndpoint);
        vm.expectRevert(IErrors.InvalidLength.selector);
        zapDest.lzReceive(srcChainId, srcAddress, nonce, payload);
    }

    function testErrors_lzReceiveRemoteNotSet() public {
        uint16 srcChainId = 1;
        bytes memory srcAddress;
        uint64 nonce = 0;
        bytes memory payload = "";

        vm.startPrank(layerZeroEndpoint);
        vm.expectRevert(IErrors.RemoteNotSet.selector);
        zapDest.lzReceive(srcChainId, srcAddress, nonce, payload);
    }

    function testErrors_lzReceiveInvalidCallerMapping() public {
        uint16 srcChainId = 1;
        bytes memory trustedAddress = abi.encode(layerZeroEndpoint);
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);

        bytes memory srcAddress = abi.encode(sender);
        uint64 nonce = 0;
        bytes memory payload = "";

        vm.startPrank(layerZeroEndpoint);
        vm.expectRevert(IErrors.InvalidCaller.selector);
        zapDest.lzReceive(srcChainId, srcAddress, nonce, payload);
    }

    function testErrors_lzReceiveInvalidFuncSelec() public {
        uint16 srcChainId = 1;
        bytes memory srcAddress = abi.encode(layerZeroEndpoint);
        uint64 nonce = 0;

        // Encode data
        bytes1 funcSelector = 0x00;
        bytes1 bridgeId = 0x00;
        bytes memory payload = abi.encode(
            funcSelector,
            bridgeId,
            sender,
            EPOCH_ID,
            EARTHQUAKE_VAULT
        );

        // Set the trusted remote
        bytes memory trustedAddress = abi.encode(layerZeroEndpoint);
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);

        vm.startPrank(layerZeroEndpoint);
        vm.expectRevert(IErrors.InvalidFunctionId.selector);
        zapDest.lzReceive(srcChainId, srcAddress, nonce, payload);
    }

    function testErrors_withdrawNullBalance() public {
        uint16 srcChainId = 1;
        bytes memory srcAddress = abi.encode(layerZeroEndpoint);
        uint64 nonce = 0;

        // Encode data
        bytes1 funcSelector = 0x01;
        bytes1 bridgeId = 0x00;
        bytes memory payload = abi.encode(
            funcSelector,
            bridgeId,
            sender,
            EPOCH_ID,
            EARTHQUAKE_VAULT
        );

        // Set the trusted remote
        bytes memory trustedAddress = abi.encode(layerZeroEndpoint);
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);

        vm.startPrank(layerZeroEndpoint);
        vm.expectRevert(IErrors.NullBalance.selector);
        zapDest.lzReceive(srcChainId, srcAddress, nonce, payload);
    }

    function testErrors_withdrawInvalidFuncSelec() public {
        // Deposits to the valut as the sender
        uint16 srcChainId = 1;
        uint64 nonce = 0;
        bytes memory srcAddress = abi.encode(layerZeroEndpoint);
        uint256 amount = _depositToVault(sender, EARTHQUAKE_VAULT);

        // Set the trusted remote
        bytes memory trustedAddress = abi.encode(layerZeroEndpoint);
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);

        // Calculate amount received in withdraw
        vm.roll(block.timestamp);
        bytes1 funcSelector = 0x04;
        bytes1 bridgeId = 0x02;
        bytes1 swapId = 0x01;
        bytes1 dexId = 0x01;
        address toToken = USDC_ADDRESS;

        bytes memory payload = abi.encode(
            funcSelector,
            bridgeId,
            sender,
            EPOCH_ID,
            EARTHQUAKE_VAULT,
            swapId,
            (amount * 9999) / 10_000,
            dexId,
            toToken,
            500
        );

        vm.startPrank(layerZeroEndpoint);
        vm.expectRevert(IErrors.InvalidFunctionId.selector);
        zapDest.lzReceive(srcChainId, srcAddress, nonce, payload);
    }

    function testErrors_withdrawInvalidSwapId() public {
        // Deposits to the valut as the sender
        uint16 srcChainId = 1;
        uint64 nonce = 0;
        bytes memory srcAddress = abi.encode(layerZeroEndpoint);
        uint256 amount = _depositToVault(sender, EARTHQUAKE_VAULT);

        // Set the trusted remote
        bytes memory trustedAddress = abi.encode(layerZeroEndpoint);
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);

        // Calculate amount received in withdraw
        vm.roll(block.timestamp);
        bytes1 funcSelector = 0x03;
        bytes1 bridgeId = 0x02;
        bytes1 swapId = 0x00;
        bytes1 dexId = 0x01;
        address toToken = USDC_ADDRESS;
        address[] memory path = new address[](2);
        path[0] = WETH_ADDRESS;
        path[1] = toToken;

        bytes memory payload = abi.encode(
            funcSelector,
            bridgeId,
            sender,
            EPOCH_ID,
            EARTHQUAKE_VAULT,
            swapId,
            (amount * 9999) / 10_000,
            dexId,
            path,
            500
        );

        vm.startPrank(layerZeroEndpoint);
        vm.expectRevert(IErrors.InvalidSwapId.selector);
        zapDest.lzReceive(srcChainId, srcAddress, nonce, payload);
    }

    function testErrors_withdrawInvalidBridgeId() public {
        // Deposits to the valut as the sender
        uint16 srcChainId = 1;
        uint64 nonce = 0;
        bytes memory srcAddress = abi.encode(layerZeroEndpoint);
        uint256 amount = _depositToVault(sender, EARTHQUAKE_VAULT);

        // Set the trusted remote
        bytes memory trustedAddress = abi.encode(layerZeroEndpoint);
        zapDest.setTrustedRemoteLookup(srcChainId, trustedAddress);

        // Calculate amount received in withdraw
        vm.roll(block.timestamp);
        bytes1 funcSelector = 0x02;
        bytes1 bridgeId = 0x04;
        bytes1 swapId = 0x00;
        bytes1 dexId = 0x01;
        address toToken = USDC_ADDRESS;

        bytes memory payload = abi.encode(
            funcSelector,
            bridgeId,
            sender,
            EPOCH_ID,
            EARTHQUAKE_VAULT,
            swapId,
            (amount * 9999) / 10_000,
            dexId,
            toToken,
            500
        );

        vm.startPrank(layerZeroEndpoint);
        vm.expectRevert(IErrors.InvalidBridgeId.selector);
        zapDest.lzReceive(srcChainId, srcAddress, nonce, payload);
    }
}
