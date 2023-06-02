// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IConnextBridge {
    function xcall(
        uint64 _destination, // Domain ID of the destination chain
        address _to, // address receiving the funds on the destination
        address _asset, // address of the token contract
        address _delegate, // address that can revert or forceLocal on destination
        uint256 _amount, // amount of tokens to transfer
        uint256 _slippage, // the maximum amount of slippage the user will accept in BPS (e.g. 30 = 0.3%)
        bytes calldata _callData // empty bytes because we're only sending funds
    ) external payable;
}
