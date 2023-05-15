// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.18;

/// @title Joe V1 Factory Interface
/// @notice Interface to interact with Joe V1 Factory
interface IJoeFactory {
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);
}
