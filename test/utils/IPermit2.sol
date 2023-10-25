// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IPermit2 {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
