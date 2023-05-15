// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IErrors {
    error InvalidMinOut(uint256 minOut);
    error InvalidInput();
    error FailedApproval();
    error FailedCall(bytes data);
    error OnlyOwner();
    error InvalidCaller();
}
