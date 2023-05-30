// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IGMXVault} from "../interfaces/IGMXVault.sol";
import {IEarthquake} from "../interfaces/IEarthquake.sol";
import {IErrors} from "../interfaces/IErrors.sol";

contract Y2KGMXZap is IErrors {
    using SafeTransferLib for ERC20;
    IGMXVault public immutable GMX_VAULT;
    address public immutable EARTHQUAKE_VAULT;

    constructor(address _gmxVault, address _earthquakeVault) {
        if (_gmxVault == address(0)) revert InvalidInput();
        if (_earthquakeVault == address(0)) revert InvalidInput();
        GMX_VAULT = IGMXVault(_gmxVault);
        EARTHQUAKE_VAULT = _earthquakeVault;
    }

    function zapIn(
        address[] calldata path,
        uint256 fromAmount,
        uint256 toAmountMin,
        uint256 id
    ) external {
        ERC20(path[0]).safeTransferFrom(
            msg.sender,
            address(GMX_VAULT),
            fromAmount
        );
        uint256 amountOut = GMX_VAULT.swap(path[0], path[1], address(this));
        if (path.length == 3) {
            ERC20(path[1]).safeTransfer(address(GMX_VAULT), amountOut);
            amountOut = GMX_VAULT.swap(path[1], path[2], address(this));
        }
        if (amountOut < toAmountMin) revert InvalidMinOut(amountOut);
        ERC20(path[path.length - 1]).safeApprove(EARTHQUAKE_VAULT, amountOut);
        IEarthquake(EARTHQUAKE_VAULT).deposit(id, amountOut, msg.sender); // NOTE: Could take receiver input
    }
}
