// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IGMXVault} from "../interfaces/dexes/IGMXVault.sol";
import {IEarthquake} from "../interfaces/IEarthquake.sol";
import {IErrors} from "../interfaces/IErrors.sol";
import {ISignatureTransfer} from "../interfaces/ISignatureTransfer.sol";
import {IPermit2} from "../interfaces/IPermit2.sol";

/// @title GMX Zap for Y2K Vaults
/// @notice Tokens can be swapped on GMX and deposited into Y2K vaults
contract Y2KGMXZap is IErrors, ISignatureTransfer {
    using SafeTransferLib for ERC20;
    IGMXVault public immutable gmxVault;
    IPermit2 public immutable permit2;

    /** @notice constructor
        @param _gmxVault The gmx vault address
        @param _permit2 The address of the permit2 contract
    **/
    constructor(address _gmxVault, address _permit2) {
        if (_gmxVault == address(0)) revert InvalidInput();
        if (_permit2 == address(0)) revert InvalidInput();
        gmxVault = IGMXVault(_gmxVault);
        permit2 = IPermit2(_permit2);
    }

    /** @notice Swaps tokens on GMX and deposits into Y2K vaults
        @param path The list of token address to swap between
        @param fromAmount The amount of fromTokens to swap
        @param toAmountMin The minimum amount of tokens to receive from the swap
        @param id The ID of the Y2K vault to deposit into
        @param vaultAddress The address of the Y2K vault to deposit into
        @param receiver The address to receive the Y2K vault shares
    **/
    function zapIn(
        address[] calldata path,
        uint256 fromAmount,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress,
        address receiver
    ) external {
        ERC20(path[0]).safeTransferFrom(
            msg.sender,
            address(gmxVault),
            fromAmount
        );
        uint256 amountOut = _swap(path, toAmountMin);
        _deposit(path[path.length - 1], id, amountOut, vaultAddress, receiver);
    }

    /** @notice Swaps tokens on GMX using permit and deposits into Y2K vaults
        @param path The list of token address to swap between
        @param toAmountMin The minimum amount of tokens to receive from the swap
        @param id The ID of the Y2K vault to deposit into
        @param vaultAddress The address of the Y2K vault to deposit into
        @param receiver The address to receive the Y2K vault shares
        @param permit The permit struct for the token being permitted plus a nonce and deadline
        @param transferDetails Struct with recipient address and amount for transfer
        @param sig The signed permit message
    **/
    function zapInPermit(
        address[] calldata path,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress,
        address receiver,
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) external {
        permit2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        uint256 amountOut = _swap(path, toAmountMin);
        _deposit(path[path.length - 1], id, amountOut, vaultAddress, receiver);
    }

    /////////////////////////////////////////
    //    INTERNAL & PRIVATE FUNCTIONS     //
    ////////////////////////////////////////
    /** @notice Deposits fromToken into a Y2K vault
        @param fromToken The ERC20 token being deposited to the vault
        @param id The ID of the Y2K vault to deposit into the vault
        @param amountIn The amount of fromToken being deposited to the vault
        @param vaultAddress The address of the Y2K vault to deposit into
        @param receiver The address to receive the Y2K vault shares
    **/
    function _deposit(
        address fromToken,
        uint256 id,
        uint256 amountIn,
        address vaultAddress,
        address receiver
    ) private {
        ERC20(fromToken).safeApprove(vaultAddress, amountIn);
        IEarthquake(vaultAddress).deposit(id, amountIn, receiver);
    }

    /** @notice Swaps tokens on GMC
        @param path An array of the tokens being swapped between
        @param toAmountMin The minimum amount of toToken to be received from the swap
        @return amountOut The amount of toToken received from the swap
    **/
    function _swap(
        address[] calldata path,
        uint256 toAmountMin
    ) private returns (uint256 amountOut) {
        amountOut = gmxVault.swap(path[0], path[1], address(this));
        if (path.length == 3) {
            ERC20(path[1]).safeTransfer(address(gmxVault), amountOut);
            amountOut = gmxVault.swap(path[1], path[2], address(this));
        }
        if (amountOut < toAmountMin) revert InvalidMinOut(amountOut);
    }
}
