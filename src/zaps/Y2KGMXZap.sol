// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IGMXVault} from "../interfaces/dexes/IGMXVault.sol";
import {IEarthquake} from "../interfaces/IEarthquake.sol";
import {IErrors} from "../interfaces/IErrors.sol";
import {ISignatureTransfer} from "../interfaces/ISignatureTransfer.sol";
import {IPermit2} from "../interfaces/IPermit2.sol";

contract Y2KGMXZap is IErrors, ISignatureTransfer {
    using SafeTransferLib for ERC20;
    IGMXVault public immutable GMX_VAULT;
    address public immutable EARTHQUAKE_VAULT;
    IPermit2 public immutable PERMIT_2;

    constructor(address _gmxVault, address _earthquakeVault, address _permit2) {
        if (_gmxVault == address(0)) revert InvalidInput();
        if (_earthquakeVault == address(0)) revert InvalidInput();
        if (_permit2 == address(0)) revert InvalidInput();
        GMX_VAULT = IGMXVault(_gmxVault);
        EARTHQUAKE_VAULT = _earthquakeVault;
        PERMIT_2 = IPermit2(_permit2);
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
        uint256 amountOut = _swap(path, toAmountMin);
        _deposit(path[path.length - 1], id, amountOut);
    }

    function zapInPermit(
        address[] calldata path,
        uint256 toAmountMin,
        uint256 id,
        PermitTransferFrom memory permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) external {
        PERMIT_2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        uint256 amountOut = _swap(path, toAmountMin);
        _deposit(path[path.length - 1], id, amountOut);
    }

    /////////////////////////////////////////
    //    INTERNAL & PRIVATE FUNCTIONS     //
    /////////////////////////////////////////

    function _deposit(address fromToken, uint256 id, uint256 amountIn) private {
        ERC20(fromToken).safeApprove(EARTHQUAKE_VAULT, amountIn);
        IEarthquake(EARTHQUAKE_VAULT).deposit(id, amountIn, msg.sender); // NOTE: Could take receiver input
    }

    function _swap(
        address[] calldata path,
        uint256 toAmountMin
    ) private returns (uint256 amountOut) {
        amountOut = GMX_VAULT.swap(path[0], path[1], address(this));
        if (path.length == 3) {
            ERC20(path[1]).safeTransfer(address(GMX_VAULT), amountOut);
            amountOut = GMX_VAULT.swap(path[1], path[2], address(this));
        }
        if (amountOut < toAmountMin) revert InvalidMinOut(amountOut);
    }
}
