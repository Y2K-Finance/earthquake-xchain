// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IErrors} from "../../interfaces/IErrors.sol";
import {IEarthquake} from "../../interfaces/IEarthquake.sol";

abstract contract VaultController is IErrors {
    using SafeTransferLib for ERC20;

    function _depositToVault(
        uint256 id,
        uint256 amount,
        address receiver,
        address inputToken,
        address vaultAddress
    ) internal {
        ERC20(inputToken).safeApprove(address(vaultAddress), amount);
        IEarthquake(vaultAddress).deposit(id, amount, receiver);
    }

    function _withdrawFromVault(
        uint256 id,
        uint256 assets,
        address receiver,
        address vaultAddress
    ) internal returns (uint256) {
        return
            IEarthquake(vaultAddress).withdraw(
                id,
                assets,
                receiver,
                address(this)
            );
    }
}
