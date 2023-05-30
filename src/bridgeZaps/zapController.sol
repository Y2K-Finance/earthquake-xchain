// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IErrors} from "../interfaces/IErrors.sol";
import {IEarthquake} from "../interfaces/IEarthquake.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";

abstract contract ZapController is IErrors {
    using SafeTransferLib for ERC20;
    IEarthquake public immutable EARTHQUAKE_VAULT;

    constructor(address _earthquakeVault) {
        if (_earthquakeVault == address(0)) revert InvalidInput();
        EARTHQUAKE_VAULT = IEarthquake(_earthquakeVault);
    }

    function _depositToVault(
        uint256 id,
        uint256 amount,
        address receiver,
        address inputToken
    ) internal {
        ERC20(inputToken).safeApprove(address(EARTHQUAKE_VAULT), amount);
        EARTHQUAKE_VAULT.deposit(id, amount, receiver);
    }
}
