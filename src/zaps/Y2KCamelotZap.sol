// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {ICamelotPair} from "../interfaces/dexes/ICamelotPair.sol";
import {IEarthquake} from "../interfaces/IEarthquake.sol";
import {IErrors} from "../interfaces/IErrors.sol";
import {ISignatureTransfer} from "../interfaces/ISignatureTransfer.sol";
import {IPermit2} from "../interfaces/IPermit2.sol";

contract Y2KCamelotZap is IErrors, ISignatureTransfer {
    using SafeTransferLib for ERC20;
    address public immutable CAMELOT_V2_FACTORY;
    IPermit2 public immutable PERMIT_2;

    constructor(address _uniswapV2Factory, address _permit2) {
        if (_uniswapV2Factory == address(0)) revert InvalidInput();
        if (_permit2 == address(0)) revert InvalidInput();
        CAMELOT_V2_FACTORY = _uniswapV2Factory;
        PERMIT_2 = IPermit2(_permit2);
    }

    /////////////////////////////////////////
    //        PUBLIC FUNCTIONS             //
    /////////////////////////////////////////
    function zapIn(
        address[] calldata path,
        uint256 fromAmount,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress
    ) external {
        ERC20(path[0]).safeTransferFrom(msg.sender, address(this), fromAmount);
        uint256 amountOut = _swap(path, fromAmount, toAmountMin);
        _deposit(path[path.length - 1], id, amountOut, vaultAddress);
    }

    function zapInPermit(
        address[] calldata path,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress,
        PermitTransferFrom memory permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) external {
        PERMIT_2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        uint256 amountOut = _swap(
            path,
            transferDetails.requestedAmount,
            toAmountMin
        );
        _deposit(path[path.length - 1], id, amountOut, vaultAddress);
    }

    /////////////////////////////////////////
    //    INTERNAL & PRIVATE FUNCTIONS     //
    /////////////////////////////////////////
    function _deposit(
        address fromToken,
        uint256 id,
        uint256 amountIn,
        address vaultAddress
    ) private {
        ERC20(fromToken).safeApprove(vaultAddress, amountIn);
        IEarthquake(vaultAddress).deposit(id, amountIn, msg.sender); // NOTE: Could take receiver input
    }

    function _swap(
        address[] calldata path,
        uint256 fromAmount,
        uint256 toAmountMin
    ) internal returns (uint256 amountOut) {
        uint256[] memory amounts = new uint256[](path.length - 1);
        address[] memory pairs = new address[](path.length - 1);

        amountOut = fromAmount;
        for (uint256 i = 0; i < path.length - 1; ) {
            {
                address fromToken = path[i];
                address toToken = path[i + 1];

                pairs[i] = _getPair(fromToken, toToken);
                (uint256 reserveA, uint256 reserveB, , ) = ICamelotPair(
                    pairs[i]
                ).getReserves();

                if (fromToken > toToken)
                    (reserveA, reserveB) = (reserveB, reserveA);

                // NOTE: Need to query the fee percent set by Camelot
                amounts[i] = ICamelotPair(pairs[i]).getAmountOut(
                    amountOut,
                    fromToken
                );
                amountOut = amounts[i];
            }

            unchecked {
                i++;
            }
        }

        if (amounts[amounts.length - 1] < toAmountMin)
            revert InvalidMinOut(amounts[amounts.length - 1]);

        SafeTransferLib.safeTransfer(ERC20(path[0]), pairs[0], fromAmount);

        return _executeSwap(path, pairs, amounts);
    }

    function _getPair(
        address tokenA,
        address tokenB
    ) internal view returns (address pair) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            CAMELOT_V2_FACTORY,
                            keccak256(abi.encodePacked(tokenA, tokenB)),
                            hex"a856464ae65f7619087bc369daaf7e387dae1e5af69cfa7935850ebf754b04c1" // init code hash
                        )
                    )
                )
            )
        );
    }

    function _executeSwap(
        address[] memory path,
        address[] memory pairs,
        uint256[] memory amounts
    ) internal returns (uint256) {
        bool zeroForOne = path[0] < path[1];
        if (pairs.length > 1) {
            ICamelotPair(pairs[0]).swap(
                zeroForOne ? 0 : amounts[0],
                zeroForOne ? amounts[0] : 0,
                pairs[1],
                ""
            );
            for (uint256 i = 1; i < pairs.length - 1; ) {
                zeroForOne = path[i] < path[i + 1];
                ICamelotPair(pairs[i]).swap(
                    zeroForOne ? 0 : amounts[i],
                    zeroForOne ? amounts[i] : 0,
                    pairs[i + 1],
                    ""
                );
                unchecked {
                    i++;
                }
            }
            zeroForOne = path[path.length - 2] < path[path.length - 1];
            ICamelotPair(pairs[pairs.length - 1]).swap(
                zeroForOne ? 0 : amounts[pairs.length - 1],
                zeroForOne ? amounts[pairs.length - 1] : 0,
                address(this),
                ""
            );
        } else {
            ICamelotPair(pairs[0]).swap(
                zeroForOne ? 0 : amounts[0],
                zeroForOne ? amounts[0] : 0,
                address(this),
                ""
            );
        }

        return amounts[amounts.length - 1];
    }
}
