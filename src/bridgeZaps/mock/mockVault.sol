// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {WETH} from "lib/solmate/src/tokens/WETH.sol";

contract MockVault {
    using SafeTransferLib for ERC20;
    ERC20 public asset;

    mapping(address => uint256) public balanceOf;

    constructor(address _asset) {
        asset = ERC20(_asset);
    }

    // FUNCTIONS //
    function depositETH(uint256, address to) external payable {
        WETH(payable(address(asset))).deposit{value: msg.value}();
        balanceOf[to] += msg.value;
    }

    function deposit(uint256, uint256 amount, address to) external {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        balanceOf[to] += amount;
    }

    function withdraw(
        uint256,
        uint256,
        address _receiver,
        address _owner
    ) external {
        if (_receiver == address(0)) revert AddressZero();
        if (msg.sender != _owner) revert Unauthorized();
        uint256 assets = balanceOf[_owner];
        asset.safeTransfer(_receiver, assets);
    }

    /// ERRORS ///
    error AddressZero();
    error Unauthorized();
}
