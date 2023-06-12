// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {UniswapV2Swapper} from "../dexHelpers/uniswapV2.sol";
import {UniswapV3Swapper} from "../dexHelpers/uniswapV3.sol";
import {CurveSwapper} from "../dexHelpers/curve.sol";

abstract contract SwapController is
    UniswapV2Swapper,
    UniswapV3Swapper,
    CurveSwapper
{
    using SafeTransferLib for ERC20;
    address public immutable BALANCER_VAULT;
    error FailedSwap();

    constructor(
        address uniswapV2Factory,
        address sushiFactory,
        address uniswapV3Factory,
        address balancerVault
    )
        UniswapV2Swapper(uniswapV2Factory, sushiFactory)
        UniswapV3Swapper((uniswapV3Factory))
    {
        BALANCER_VAULT = balancerVault;
    }

    function _swap(
        bytes1 dexId,
        uint256 fromAmount,
        bytes calldata swapPayload
    ) internal returns (uint256) {
        if (dexId == 0x01) return _swapUniswapV2(0x01, fromAmount, swapPayload);
        else if (dexId == 0x02) return _swapUniswapV3(fromAmount, swapPayload);
        else if (dexId == 0x03)
            return _swapUniswapV2(0x02, fromAmount, swapPayload);
        // Sushiswap logic
        else if (dexId == 0x04) return _swapWithCurve(swapPayload);
        else if (dexId == 0x05) {
            (bool success, bytes memory data) = BALANCER_VAULT.call(
                swapPayload
            );
            if (!success) revert FailedSwap();
            if (keccak256(swapPayload[0:4]) == keccak256("0x52bbbe29")) {
                return abi.decode(data, (uint256));
            } else {
                int256[] memory assetDeltas = abi.decode(data, (int256[]));
                for (uint256 i = 0; i < assetDeltas.length; ) {
                    if (assetDeltas[i] < 0) return uint256(-assetDeltas[i]);
                    unchecked {
                        i++;
                    }
                }
                revert FailedSwap();
            }
        } else revert InvalidInput();
    }
}
