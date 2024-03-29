// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SwapHelper, ERC20, IGMXVault, ICamelotPair, IUniswapPair, IBalancerVault, IEarthQuakeVault, IERC1155, Y2KCamelotZap, Y2KUniswapV2Zap, Y2KChronosZap, Y2KBalancerZap, Y2KUniswapV3Zap, Y2KTraderJoeZap, Y2KCurveZap, Y2KGMXZap, Y2KvlZap} from "../utils/SwapUtils.sol";
import {ISignatureTransfer} from "../../src/interfaces/ISignatureTransfer.sol";
import {IErrors} from "../../src/interfaces/IErrors.sol";
import {IPermit2 as Permit2} from "../../src/interfaces/IPermit2.sol";
import {IvlY2K} from "../utils/Interfaces.sol";

contract ZapTests is SwapHelper {
    /////////////////////////////////////////
    //               CONFIG                //
    /////////////////////////////////////////
    function forkAndConfig() public {
        assertEq(vm.activeFork(), arbitrumFork);
        assertEq(ERC20(USDC_ADDRESS).symbol(), "USDC");
        assertEq(
            IEarthQuakeVault(EARTHQUAKE_VAULT).controller(),
            EARTHQUAKE_CONTROLLER
        );
        assertEq(
            IEarthQuakeVault(EARTHQUAKE_VAULT).idEpochBegin(EPOCH_ID),
            EPOCH_BEGIN
        );
        assertEq(block.timestamp, EPOCH_BEGIN - 1);
    }

    /////////////////////////////////////////
    //               vlY2K Tests            //
    /////////////////////////////////////////
    function test_depositvlY2K() private {
        vm.startPrank(sender);
        (
            uint256 y2kBalance,
            uint256 wethBalance,
            uint256 assetOneAmount,
            uint256 assetTwoAmount,
            IBalancerVault.JoinPoolRequest memory request
        ) = _setupvlY2K(sender);

        uint256 pid = 1544044071929306331074;
        zapvlY2K.zapIn(
            request,
            Y2K_WETH_POOL_ID_BALANCER,
            assetOneAmount,
            assetTwoAmount,
            pid
        );

        assertTrue(IERC20(Y2K_ADDRESS).balanceOf(sender) < y2kBalance);
        assertTrue(IERC20(WETH_ADDRESS).balanceOf(sender) < wethBalance);
        (uint256 accountBalance, , , , ) = IvlY2K(VL_Y2K).getAccount(sender);
        assertGe(accountBalance, 0);
        vm.stopPrank();
    }

    /////////////////////////////////////////
    //               STATE VARS            //
    /////////////////////////////////////////

    function testStateVars_Camelot() public {
        assertEq(zapCamelot.camelotV2Factory(), CAMELOT_FACTORY);
        assertEq(address(zapCamelot.permit2()), PERMIT_2);
    }

    function testStateVars_Sushi() public {
        assertEq(zapSushiV2.uniswapV2ForkFactory(), SUSHI_V2_FACTORY);
        assertEq(address(zapSushiV2.permit2()), PERMIT_2);
    }

    function testStateVars_Balancer() public {
        assertEq(address(zapBalancer.balancerVault()), BALANCER_VAULT);
        assertEq(address(zapBalancer.permit2()), PERMIT_2);
    }

    function testStateVars_UniswapV3() public {
        assertEq(zapUniswapV3.uniswapV3Factory(), UNISWAP_V3_FACTORY);
        assertEq(address(zapUniswapV3.permit2()), PERMIT_2);
    }

    function testStateVars_Curve() public {
        assertEq(address(zapCurve.permit2()), PERMIT_2);
        assertEq(zapCurve.wethAddress(), WETH_ADDRESS);
    }

    function testStateVars_GMX() public {
        assertEq(address(zapGMX.gmxVault()), GMX_VAULT);
        assertEq(address(zapGMX.permit2()), PERMIT_2);
    }

    function testStateVars_TraderJoe() public {
        assertEq(address(zapTraderJoe.legacyFactory()), TJ_LEGACY_FACTORY);
        assertEq(address(zapTraderJoe.factory()), TJ_FACTORY);
        assertEq(address(zapTraderJoe.factoryV1()), TJ_FACTORY_V1);
    }

    function testStateVars_Chronos() public {
        assertEq(zapChronos.chronosFactory(), CHRONOS_FACTORY);
    }

    function testStateVars_vlZapper() public {
        assertEq(address(zapvlY2K.balancerVault()), BALANCER_VAULT);
        assertEq(address(zapvlY2K.permit2()), PERMIT_2);
        assertEq(address(zapvlY2K.lpAsset()), BALANCER_Y2K_LP_TOKEN);
    }

    /////////////////////////////////////////
    //                 ERRORS              //
    /////////////////////////////////////////

    function testErrors_Camelot() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KCamelotZap(address(0), PERMIT_2);

        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KCamelotZap(CAMELOT_FACTORY, address(0));

        vm.startPrank(sender);
        (
            address[] memory path,
            uint256 fromAmount,
            ,
            uint256 id
        ) = setupUSDCtoWETHV2Fork(address(zapCamelot), sender);

        // Dynamically fetch the amountOut
        uint256 amountOut = ICamelotPair(CAMELOT_USDC_WETH_PAIR).getAmountOut(
            fromAmount,
            path[0]
        );

        // Execute revert with dynamic data
        vm.expectRevert(
            abi.encodePacked(IErrors.InvalidMinOut.selector, amountOut)
        );
        zapCamelot.zapIn(
            path,
            fromAmount,
            amountOut + 1,
            id,
            EARTHQUAKE_VAULT,
            sender
        );
    }

    function testErrors_Sushi() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KUniswapV2Zap(address(0), PERMIT_2);

        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KUniswapV2Zap(SUSHI_V2_FACTORY, address(0));

        vm.startPrank(sender);
        (
            address[] memory path,
            uint256 fromAmount,
            ,
            uint256 id
        ) = setupUSDCtoWETHV2Fork(address(zapSushiV2), sender);

        // Dynamically fetch the amountOut
        (uint256 reserveA, uint256 reserveB, ) = IUniswapPair(
            SUSHI_USDC_WETH_PAIR
        ).getReserves();
        if (path[0] > path[1]) (reserveA, reserveB) = (reserveB, reserveA);
        uint256 amountOut = ((fromAmount * 997) * reserveB) /
            ((reserveA * 1000) + (fromAmount * 997));

        // Execute the revert with dynamic data
        vm.expectRevert(
            abi.encodePacked(IErrors.InvalidMinOut.selector, amountOut)
        );
        zapSushiV2.zapIn(
            path,
            fromAmount,
            amountOut + 1,
            id,
            EARTHQUAKE_VAULT,
            sender
        );
    }

    function testErrors_UniswapV3() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KUniswapV3Zap(address(0), PERMIT_2);

        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KUniswapV3Zap(UNISWAP_V3_FACTORY, address(0));

        // // staging for revert test
        // vm.startPrank(sender);
        // (
        //     address[] memory path,
        //     uint24[] memory fee,
        //     uint256 fromAmount,
        //     ,
        //     uint256 id
        // ) = setupUSDCtoWETHV3(address(zapUniswapV3));

        // // Dynamically fetch the amountOut
        // // TODO: Best way to fetch the dynamic value?
        // uint256 amountOut = 0;

        // // Execute the revert with dynamic data
        // vm.expectRevert(
        //     abi.encodePacked(IErrors.InvalidMinOut.selector, amountOut)
        // );
        // zapUniswapV3.zapIn(path, fee, fromAmount, toAmountMin, id);

        bytes memory data = abi.encode(USDC_ADDRESS, WETH_ADDRESS, 500);
        vm.expectRevert(IErrors.InvalidCaller.selector);
        zapUniswapV3.uniswapV3SwapCallback(100, 100, data);
    }

    function testErrors_Balancer() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KBalancerZap(address(0), PERMIT_2);

        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KBalancerZap(BALANCER_VAULT, address(0));
    }

    function testErrors_Curve() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KCurveZap(address(0), PERMIT_2);

        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KCurveZap(WETH_ADDRESS, address(0));

        // TODO: Invalid output from swap to wrong type of pool (zapInSingle)

        // staging for zapInSingles (Standard and ETH)
        vm.startPrank(sender);
        (
            address fromToken,
            ,
            uint256 i,
            uint256 j,
            address pool,
            uint256 fromAmount,
            uint256 toAmountMin,
            uint256 id
        ) = setupUSDTtoWETHCurve(
                address(zapCurveUSDT),
                EARTHQUAKE_VAULT_USDT,
                sender
            );

        vm.expectRevert(IErrors.InvalidOutput.selector);
        zapCurveUSDT.zapIn(
            fromToken,
            FRAX_ADDRESS,
            i,
            j,
            pool,
            fromAmount,
            toAmountMin,
            id,
            EARTHQUAKE_VAULT_USDT,
            sender
        );

        vm.expectRevert(IErrors.InvalidOutput.selector);
        zapCurveUSDT.zapIn(
            fromToken,
            FRAX_ADDRESS,
            i,
            j,
            pool,
            fromAmount,
            toAmountMin,
            id,
            EARTHQUAKE_VAULT_USDT,
            sender
        );

        (
            address[] memory path,
            address[] memory pools,
            uint256[] memory iValues,
            uint256[] memory jValues,
            ,
            ,

        ) = setupUSDCtoUSDTtoWETHCurve(
                address(zapCurveUSDT),
                EARTHQUAKE_VAULT_USDT,
                sender
            );

        // changing amountOut to revert
        Y2KCurveZap.MultiSwapInfo memory multiSwapInfo;
        multiSwapInfo.path = path;
        multiSwapInfo.pools = pools;
        multiSwapInfo.iValues = iValues;
        multiSwapInfo.jValues = jValues;
        multiSwapInfo.toAmountMin = 100 ether;
        multiSwapInfo.vaultAddress = EARTHQUAKE_VAULT_USDT;

        vm.expectRevert(bytes("Slippage"));
        zapCurveUSDT.zapInMulti(fromAmount, id, multiSwapInfo);

        multiSwapInfo.path[2] = FRAX_ADDRESS;
        vm.expectRevert(IErrors.InvalidOutput.selector);
        zapCurveUSDT.zapInMulti(fromAmount, id, multiSwapInfo);

        // TODO: Invalid output from swap to wrong type of pool (zapInMulti)
    }

    function testErrors_GMX() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KGMXZap(address(0), PERMIT_2);

        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KGMXZap(EARTHQUAKE_VAULT, address(0));

        // staging the revert test
        vm.startPrank(sender);
        (
            address[] memory path,
            uint256 fromAmount,
            ,
            uint256 id
        ) = setupUSDCtoWETHV2Fork(address(zapGMX), sender); // NOTE: Uses the same inputs as V2 forks

        // Dynamically fetch the amountOut
        uint256 priceIn = IGMXVault(GMX_VAULT).getMinPrice(path[0]);
        uint256 priceOut = IGMXVault(GMX_VAULT).getMaxPrice(path[1]);
        uint256 amountOut = (fromAmount * priceIn) / priceOut;
        amountOut = (amountOut * (10 ** 18)) / (10 ** 6);

        // amount after fees
        amountOut =
            (amountOut * (BASIS_POINTS_DIVISOR - 34)) /
            BASIS_POINTS_DIVISOR;

        vm.expectRevert(
            abi.encodePacked(IErrors.InvalidMinOut.selector, amountOut)
        );
        zapGMX.zapIn(
            path,
            fromAmount,
            amountOut + 1,
            id,
            EARTHQUAKE_VAULT,
            sender
        );
    }

    function testErrors_TraderJoe() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KTraderJoeZap(address(0), TJ_FACTORY, TJ_FACTORY_V1);

        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KTraderJoeZap(TJ_LEGACY_FACTORY, address(0), TJ_FACTORY_V1);

        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KTraderJoeZap(TJ_LEGACY_FACTORY, TJ_FACTORY, address(0));

        // TODO: InvalidMinOut from (zapIn)
        // TODO: InvalidPair from _getPair
        // TODO: InvalidPair from _getLBPairInformation
    }

    function testErrors_Chronos() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KChronosZap(address(0));
    }

    function testErrors_vlY2K() public {
        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KvlZap(address(0), PERMIT_2, VL_Y2K, BALANCER_Y2K_LP_TOKEN);

        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KvlZap(BALANCER_VAULT, address(0), VL_Y2K, BALANCER_Y2K_LP_TOKEN);

        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KvlZap(
            BALANCER_VAULT,
            PERMIT_2,
            address(0),
            BALANCER_Y2K_LP_TOKEN
        );

        vm.expectRevert(IErrors.InvalidInput.selector);
        new Y2KvlZap(BALANCER_VAULT, PERMIT_2, VL_Y2K, address(0));
    }

    /////////////////////////////////////////
    //              PERMIT                //
    /////////////////////////////////////////
    function testCorrectWitnessTypehash() public {
        assertEq(
            keccak256(
                abi.encodePacked(
                    _PERMIT_TRANSFER_TYPEHASH_STUB,
                    WITNESS_TYPE_STRING
                )
            ),
            FULL_EXAMPLE_WITNESS_TYPEHASH
        );
    }

    function test_PermitTransfer() public {
        vm.startPrank(permitSender);
        uint256 fromAmount = 10e6;

        deal(USDC_ADDRESS, permitSender, fromAmount);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(permitSender), fromAmount);

        (
            ISignatureTransfer.PermitTransferFrom memory permit,
            ISignatureTransfer.SignatureTransferDetails memory transferDetails,
            bytes memory sig
        ) = setupPermitSwap(
                permitReceiver,
                permitReceiver,
                fromAmount,
                USDC_ADDRESS
            );
        vm.startPrank(permitReceiver);
        Permit2(PERMIT_2).permitTransferFrom(
            permit,
            transferDetails,
            permitSender,
            sig
        );

        assertEq(IERC20(USDC_ADDRESS).balanceOf(permitSender), 0);
        assertEq(IERC20(USDC_ADDRESS).balanceOf(permitReceiver), fromAmount);
        vm.stopPrank();
    }
}
