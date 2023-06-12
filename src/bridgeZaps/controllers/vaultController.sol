// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IErrors} from "../../interfaces/IErrors.sol";
import {IEarthquake} from "../../interfaces/IEarthquake.sol";

abstract contract VaultController is IErrors {
    using SafeTransferLib for ERC20;
    IEarthquake public immutable earthquakeVault;

    constructor(address _earthquakeVault) {
        if (_earthquakeVault == address(0)) revert InvalidInput();
        earthquakeVault = IEarthquake(_earthquakeVault);
    }

    function _depositToVault(
        uint256 id,
        uint256 amount,
        address receiver,
        address inputToken
    ) internal {
        ERC20(inputToken).safeApprove(address(earthquakeVault), amount);
        earthquakeVault.deposit(id, amount, receiver);
    }

    function _withdrawFromVault(
        uint256 id,
        uint256 assets,
        address receiver
    ) internal returns (uint256) {
        return earthquakeVault.withdraw(id, assets, receiver, address(this));
    }
}
