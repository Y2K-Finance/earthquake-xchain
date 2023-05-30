// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {ICamelotPair} from "../interfaces/ICamelotPair.sol";
import {IEarthquake} from "../interfaces/IEarthquake.sol";
import {IErrors} from "../interfaces/IErrors.sol";

contract Y2KCamelotZap is IErrors {
    using SafeTransferLib for ERC20;
    address public immutable CAMELOT_V2_FACTORY;
    address public immutable EARTHQUAKE_VAULT;

    constructor(address _uniswapV2Factory, address _earthquakeVault) {
        if (_uniswapV2Factory == address(0)) revert InvalidInput();
        if (_earthquakeVault == address(0)) revert InvalidInput();
        CAMELOT_V2_FACTORY = _uniswapV2Factory;
        EARTHQUAKE_VAULT = _earthquakeVault;
    }

    function zapIn(
        address[] calldata path,
        uint256 fromAmount,
        uint256 toAmountMin,
        uint256 id
    ) external {
        ERC20(path[0]).safeTransferFrom(msg.sender, address(this), fromAmount);
        uint256 amountOut = _swap(path, fromAmount, toAmountMin);
        ERC20(path[path.length - 1]).safeApprove(EARTHQUAKE_VAULT, amountOut);
        IEarthquake(EARTHQUAKE_VAULT).deposit(id, amountOut, msg.sender); // NOTE: Could take receiver input
    }

    function _swap(
        address[] calldata path,
        uint256 fromAmount,
        uint256 toAmountMin
    ) internal returns (uint256 amountOut) {
        uint256[] memory amounts = new uint256[](path.length - 1);
        address[] memory pairs = new address[](path.length - 1);

        // TODO: More efficent way to use this amount?
        uint256 cachedFrom = fromAmount;

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
                    cachedFrom,
                    fromToken
                );
                cachedFrom = amounts[i];
            }

            unchecked {
                i++;
            }
        }

        if (amounts[amounts.length - 1] < toAmountMin)
            revert InvalidMinOut(amounts[amounts.length - 1]);

        SafeTransferLib.safeTransfer(ERC20(path[0]), pairs[0], fromAmount);

        // NOTE: Abstract into own function
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

        amountOut = amounts[amounts.length - 1];
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
}