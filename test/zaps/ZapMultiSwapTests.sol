// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {SwapHelper, IERC20} from "../utils/SwapUtils.sol";
import {IERC1155} from "../utils/Interfaces.sol";
import {Y2KCurveZap} from "../../src/zaps/Y2KCurveZap.sol";
import {IBalancerVault} from "../../src/interfaces/dexes/IBalancerVault.sol";
import {ISignatureTransfer} from "../../src/interfaces/ISignatureTransfer.sol";
import {IPermit2 as Permit2} from "../../src/interfaces/IPermit2.sol";

contract ZapSwapMultiTest is SwapHelper {
    function test_MultiswapAndDepositCamelot() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupUSDCtoUSDTtoWETHV2Fork(address(zapCamelot));

        zapCamelot.zapIn(
            path,
            fromAmount,
            toAmountMin,
            id,
            EARTHQUAKE_VAULT,
            depositReceiver
        );
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(depositReceiver, id), 1);
        vm.stopPrank();
    }

    function test_Multiswap3xAndDepositCamelot() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupDAItoUSDCtoUSDTtoWETHV2Fork(address(zapCamelot));

        zapCamelot.zapIn(
            path,
            fromAmount,
            toAmountMin,
            id,
            EARTHQUAKE_VAULT,
            depositReceiver
        );
        assertEq(IERC20(DAI_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(depositReceiver, id), 1);
        vm.stopPrank();
    }

    function test_MultiswapAndDepositSushiV2() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupUSDCtoUSDTtoWETHV2Fork(address(zapSushiV2));

        zapSushiV2.zapIn(
            path,
            fromAmount,
            toAmountMin,
            id,
            EARTHQUAKE_VAULT,
            depositReceiver
        );
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(depositReceiver, id), 1);
        vm.stopPrank();
    }

    function test_Multiswap3xAndDepositSushiV2() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupWETHtoUSDCtoUSDTtoWETHV2Fork(address(zapSushiV2));

        zapSushiV2.zapIn(
            path,
            fromAmount,
            toAmountMin,
            id,
            EARTHQUAKE_VAULT,
            depositReceiver
        );
        assertEq(IERC20(WETH_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(depositReceiver, id), 1);
        vm.stopPrank();
    }

    function test_MultiswapAndDepositUniswapV3() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            uint24[] memory fee,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupUSDCtoUSDTtoWETHV3(address(zapUniswapV3));

        zapUniswapV3.zapIn(
            path,
            fee,
            fromAmount,
            toAmountMin,
            id,
            EARTHQUAKE_VAULT,
            depositReceiver
        );
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(depositReceiver, id), 1);
        vm.stopPrank();
    }

    function test_Multiswap3xAndDepositUniswapV3() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            uint24[] memory fee,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupDAItoUSDCtoUSDTtoWETHV3(address(zapUniswapV3));

        zapUniswapV3.zapIn(
            path,
            fee,
            fromAmount,
            toAmountMin,
            id,
            EARTHQUAKE_VAULT,
            depositReceiver
        );
        assertEq(IERC20(DAI_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(depositReceiver, id), 1);
        vm.stopPrank();
    }

    function test_MultiswapAndDepositBalancer() public {
        vm.startPrank(sender);
        (
            IBalancerVault.SwapKind kind,
            IBalancerVault.BatchSwapStep[] memory batchSwap,
            address[] memory assets,
            int256[] memory limits,
            uint256 deadline,
            uint256 id
        ) = setupUSDTtoUSDCtoWETHBalancer(address(zapBalancer), sender);

        zapBalancer.zapInMulti(
            kind,
            batchSwap,
            assets,
            limits,
            deadline,
            id,
            EARTHQUAKE_VAULT,
            depositReceiver
        );
        assertEq(IERC20(USDT_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(depositReceiver, id), 1);
        vm.stopPrank();
    }

    function test_Multiswap3xAndDepositBalancer() public {
        vm.startPrank(sender);
        (
            IBalancerVault.SwapKind kind,
            IBalancerVault.BatchSwapStep[] memory batchSwap,
            address[] memory assets,
            int256[] memory limits,
            uint256 deadline,
            uint256 id
        ) = setupDUSDtoUSDTtoUSDCtoWETHBalancer(address(zapBalancer));

        zapBalancer.zapInMulti(
            kind,
            batchSwap,
            assets,
            limits,
            deadline,
            id,
            EARTHQUAKE_VAULT,
            depositReceiver
        );
        assertEq(IERC20(DUSD_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(depositReceiver, id), 1);
        vm.stopPrank();
    }

    function test_MultiswapAndDepositCurve() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            address[] memory pools,
            uint256[] memory iValues,
            uint256[] memory jValues,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupUSDCtoUSDTtoWETHCurve(
                address(zapCurveUSDT),
                EARTHQUAKE_VAULT_USDT,
                sender
            );

        Y2KCurveZap.MultiSwapInfo memory multiSwapInfo;
        multiSwapInfo.path = path;
        multiSwapInfo.pools = pools;
        multiSwapInfo.iValues = iValues;
        multiSwapInfo.jValues = jValues;
        multiSwapInfo.toAmountMin = toAmountMin;
        multiSwapInfo.vaultAddress = EARTHQUAKE_VAULT_USDT;
        multiSwapInfo.receiver = depositReceiver;

        zapCurveUSDT.zapInMulti(fromAmount, id, multiSwapInfo);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 0);
        assertGe(
            IERC1155(EARTHQUAKE_VAULT_USDT).balanceOf(depositReceiver, id),
            1
        );
        vm.stopPrank();
    }

    function test_Multiswap3xAndDepositCurve() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            address[] memory pools,
            uint256[] memory iValues,
            uint256[] memory jValues,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupFRAXtoUSDCtoUSDTtoWETHCurve(
                address(zapCurveUSDT),
                EARTHQUAKE_VAULT_USDT
            );

        Y2KCurveZap.MultiSwapInfo memory multiSwapInfo;
        multiSwapInfo.path = path;
        multiSwapInfo.pools = pools;
        multiSwapInfo.iValues = iValues;
        multiSwapInfo.jValues = jValues;
        multiSwapInfo.toAmountMin = toAmountMin;
        multiSwapInfo.vaultAddress = EARTHQUAKE_VAULT_USDT;
        multiSwapInfo.receiver = depositReceiver;

        zapCurveUSDT.zapInMulti(fromAmount, id, multiSwapInfo);
        assertEq(IERC20(FRAX_ADDRESS).balanceOf(sender), 0);
        assertGe(
            IERC1155(EARTHQUAKE_VAULT_USDT).balanceOf(depositReceiver, id),
            1
        );
        vm.stopPrank();
    }

    function test_MultiswapAndDepositGMX() public {
        vm.startPrank(sender);
        (
            address[] memory path,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupUSDCtoUSDTtoWETHV2Fork(address(zapGMX)); // NOTE: Uses the same inputs as V2 forks

        zapGMX.zapIn(
            path,
            fromAmount,
            toAmountMin,
            id,
            EARTHQUAKE_VAULT,
            sender
        );
        assertEq(IERC20(USDC_ADDRESS).balanceOf(sender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(sender, id), 1);
        vm.stopPrank();
    }

    /////////////////////////////////////////
    //          ZAP with PERMIT            //
    ////////////////////////////////////////
    function test_PermitMultiswapAndDepositBalancer() public {
        vm.startPrank(permitSender);
        (
            IBalancerVault.SwapKind kind,
            IBalancerVault.BatchSwapStep[] memory batchSwap,
            address[] memory assets,
            int256[] memory limits,
            ,
            uint256 id
        ) = setupUSDTtoUSDCtoWETHBalancer(address(zapBalancer), permitSender);
        (
            ISignatureTransfer.PermitTransferFrom memory permit,
            ISignatureTransfer.SignatureTransferDetails memory transferDetails,
            bytes memory sig
        ) = setupPermitSwap(
                address(zapBalancer),
                address(zapBalancer),
                batchSwap[0].amount,
                USDT_ADDRESS
            );

        zapBalancer.zapInMultiPermit(
            kind,
            batchSwap,
            assets,
            limits,
            id,
            EARTHQUAKE_VAULT,
            permitReceiver,
            permit,
            transferDetails,
            sig
        );
        assertEq(IERC20(USDT_ADDRESS).balanceOf(permitSender), 0);
        assertGe(IERC1155(EARTHQUAKE_VAULT).balanceOf(permitReceiver, id), 1);
        vm.stopPrank();
    }

    function test_PermitMultiswapAndDepositCurve() public {
        vm.startPrank(permitSender);
        (
            address[] memory path,
            address[] memory pools,
            uint256[] memory iValues,
            uint256[] memory jValues,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupUSDCtoUSDTtoWETHCurve(
                address(zapCurveUSDT),
                EARTHQUAKE_VAULT_USDT,
                permitSender
            );
        (
            ISignatureTransfer.PermitTransferFrom memory permit,
            ISignatureTransfer.SignatureTransferDetails memory transferDetails,
            bytes memory sig
        ) = setupPermitSwap(
                address(zapCurveUSDT),
                address(zapCurveUSDT),
                fromAmount,
                USDC_ADDRESS
            );

        Y2KCurveZap.MultiSwapInfo memory multiSwapInfo;
        multiSwapInfo.path = path;
        multiSwapInfo.pools = pools;
        multiSwapInfo.iValues = iValues;
        multiSwapInfo.jValues = jValues;
        multiSwapInfo.toAmountMin = toAmountMin;
        multiSwapInfo.vaultAddress = EARTHQUAKE_VAULT_USDT;
        multiSwapInfo.receiver = permitReceiver;

        zapCurveUSDT.zapInMultiPermit(
            id,
            multiSwapInfo,
            permit,
            transferDetails,
            sig
        );
        assertEq(IERC20(USDC_ADDRESS).balanceOf(permitSender), 0);
        assertGe(
            IERC1155(EARTHQUAKE_VAULT_USDT).balanceOf(permitReceiver, id),
            1
        );
        vm.stopPrank();
    }
}
