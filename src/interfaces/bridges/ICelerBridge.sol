// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ICelerBridge {
    function send(
        address _receiver,
        address _token,
        uint256 _amount,
        uint16 _dstChainId,
        uint256 _nonce,
        uint256 _maxSlippage
    ) external;
}
