// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ILBFactory} from "./ILBFactory.sol";

interface ILBPair {
    function getFactory() external view returns (ILBFactory factory);

    function getTokenX() external view returns (IERC20 tokenX);

    function getTokenY() external view returns (IERC20 tokenY);

    function getBinStep() external view returns (uint16 binStep);

    function getReserves()
        external
        view
        returns (uint128 reserveX, uint128 reserveY);

    function getSwapIn(
        uint128 amountOut,
        bool swapForY
    )
        external
        view
        returns (uint128 amountIn, uint128 amountOutLeft, uint128 fee);

    function getSwapOut(
        uint128 amountIn,
        bool swapForY
    )
        external
        view
        returns (uint128 amountInLeft, uint128 amountOut, uint128 fee);

    function swap(
        bool swapForY,
        address to
    ) external returns (bytes32 amountsOut);
}
