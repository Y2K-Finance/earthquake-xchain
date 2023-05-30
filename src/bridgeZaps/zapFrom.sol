// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IErrors} from "../interfaces/IErrors.sol";
import {IStargateRouter} from "../interfaces/IStargateRouter.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";

contract ZapFrom is IErrors {
    using SafeTransferLib for ERC20;
    // TODO: Best way to use a uint16 for the input in router?
    uint256 public constant ARBITRUM_CHAIN_ID = 42161;
    // TODO: Value must be abi.encodePacked(bytes);
    // TODO: Review the destStargateComposed construction which we substitute ARB_RECEIVER for
    bytes public constant ARB_RECEIVER = "0x00";
    address public immutable STARGATE_ROUTER;

    constructor(address stargateRouter) {
        if (stargateRouter == address(0)) revert InvalidInput();
        STARGATE_ROUTER = stargateRouter;
    }

    /// @param amountIn The qty of local _token contract tokens
    /// @param fromToken The fromChain token address
    /// @param srcPoolId The poolId for the fromChain
    /// @param dstPoolId The poolId for the toChain
    /// @param payload The encoded payload to deposit into vault abi.encode(receiver, vaultId)
    function zapWithStargate(
        uint amountIn,
        address fromToken,
        uint16 srcPoolId,
        uint16 dstPoolId,
        bytes calldata payload
    ) external payable {
        if (msg.value == 0) revert InvalidInput();
        if (amountIn == 0) revert InvalidInput();

        ERC20(fromToken).safeTransferFrom(msg.sender, address(this), amountIn);
        ERC20(fromToken).safeApprove(STARGATE_ROUTER, amountIn);

        // Sends tokens to the destChain
        IStargateRouter(STARGATE_ROUTER).swap{value: msg.value}(
            uint16(ARBITRUM_CHAIN_ID), // the destination chain id
            srcPoolId, // the source Stargate poolId
            dstPoolId, // the destination Stargate poolId
            payable(msg.sender), // refund adddress. if msg.sender pays too much gas, return extra eth
            amountIn, // total tokens to send to destination chain
            0, // min amount allowed out
            IStargateRouter.lzTxObj(200000, 0, "0x"), // default lzTxObj
            ARB_RECEIVER, // destination address, the sgReceive() implementer
            payload
        );
    }
}
