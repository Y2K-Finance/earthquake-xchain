// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IBalancerVault} from "../interfaces/dexes/IBalancerVault.sol";
import {IvlY2K} from "../interfaces/IvlY2K.sol";
import {IErrors} from "../interfaces/IErrors.sol";
import {ISignatureTransfer} from "../interfaces/ISignatureTransfer.sol";
import {IPermit2} from "../interfaces/IPermit2.sol";

contract Y2KvlZap is IErrors, ISignatureTransfer {
    using SafeTransferLib for ERC20;
    IBalancerVault public immutable balancerVault;
    IPermit2 public immutable permit2;
    IvlY2K public immutable vlY2K;
    ERC20 public immutable lpAsset;

    constructor(
        address _balancerVault,
        address _permit2,
        address _vlY2K,
        address _lpAsset
    ) {
        if (_balancerVault == address(0)) revert InvalidInput();
        if (_permit2 == address(0)) revert InvalidInput();
        if (_vlY2K == address(0)) revert InvalidInput();
        if (_lpAsset == address(0)) revert InvalidInput();
        balancerVault = IBalancerVault(_balancerVault);
        permit2 = IPermit2(_permit2);
        vlY2K = IvlY2K(_vlY2K);
        lpAsset = ERC20(_lpAsset);
    }

    // TODO: Compare gas with uint256[2] vs. uint256 and uint256
    // TODO: Could make the assets immutable as they will be the same
    function zapIn(
        IBalancerVault.JoinPoolRequest calldata request,
        bytes32 poolId,
        uint256 assetOneAmount,
        uint256 assetTwoAmount,
        uint256 id
    ) external {
        ERC20 assetOne = ERC20(request.assets[0]);
        ERC20 assetTwo = ERC20(request.assets[1]);
        _transferAndApprove(assetOne, assetTwo, assetOneAmount, assetTwoAmount);
        uint256 amountOut = balancerVault.joinPool(
            poolId,
            address(this),
            address(this),
            request
        );
        _deposit(id, amountOut); // TODO: vl needs a receiver
        _refund(assetOne, assetTwo);
    }

    // TODO: Compare gas with uint256[2] vs. uint256 and uint256
    // TODO: Could make the assets immutable as they will be the same
    function zapInPermit(
        IBalancerVault.JoinPoolRequest calldata request,
        bytes32 poolId,
        uint256 id,
        uint256[2] calldata assetAmounts,
        PermitTransferFrom[2] calldata permit,
        SignatureTransferDetails[2] calldata transferDetails,
        bytes[2] calldata sig
    ) external {
        ERC20 assetOne = ERC20(request.assets[0]);
        ERC20 assetTwo = ERC20(request.assets[1]);
        _permitTransferAndApprove(
            assetOne,
            assetAmounts[0],
            permit[0],
            transferDetails[0],
            sig[0]
        );
        _permitTransferAndApprove(
            assetTwo,
            assetAmounts[1],
            permit[1],
            transferDetails[1],
            sig[1]
        );
        uint256 amountOut = balancerVault.joinPool(
            poolId,
            address(this),
            address(this),
            request
        );
        _deposit(id, amountOut); // TODO: vl needs a receiver
        _refund(assetOne, assetTwo);
    }

    /////////////////////////////////////////
    //    INTERNAL & PRIVATE FUNCTIONS     //
    /////////////////////////////////////////
    function _transferAndApprove(
        ERC20 assetOne,
        ERC20 assetTwo,
        uint256 assetOneAmount,
        uint256 assetTwoAmount
    ) internal {
        assetOne.safeTransferFrom(msg.sender, address(this), assetOneAmount);
        assetOne.safeApprove(address(balancerVault), assetOneAmount);
        assetTwo.safeTransferFrom(msg.sender, address(this), assetTwoAmount);
        assetTwo.safeApprove(address(balancerVault), assetTwoAmount);
    }

    function _permitTransferAndApprove(
        ERC20 fromToken,
        uint256 fromAmount,
        PermitTransferFrom memory permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) internal {
        permit2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        fromToken.safeApprove(address(balancerVault), fromAmount);
    }

    function _deposit(uint256 id, uint256 amountIn) private {
        lpAsset.safeApprove(address(vlY2K), amountIn);
        vlY2K.deposit(id, amountIn);
    }

    function _refund(ERC20 assetOne, ERC20 assetTwo) private {
        if (assetOne.balanceOf(address(this)) > 0)
            assetOne.safeTransfer(
                msg.sender,
                assetOne.balanceOf(address(this))
            );
        if (assetTwo.balanceOf(address(this)) > 0)
            assetTwo.safeTransfer(
                msg.sender,
                assetTwo.balanceOf(address(this))
            );
    }
}
