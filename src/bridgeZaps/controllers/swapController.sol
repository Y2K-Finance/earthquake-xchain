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
    address public immutable balancerVault;
    error FailedSwap();

    /** @notice Invoked in zapFrom constructor 
        @dev DEX constructors are invoked in this call - UniswapV2 (uniV2 and sushi), UniswapV3, Curve
        @param _uniswapV2Factory The uniswapv2 factory address
        @param _sushiFactory The sushiswap factory address
        @param _uniswapV3Factory The uniswapv3 factory address
        @param _balancerVault The balancer vault address
        @param _wethAddress The weth address
        @param _primaryInitHash The init code hash for uniswapv2
        @param _secondaryInitHash The init code hash for sushiswap
     **/
    constructor(
        address _uniswapV2Factory,
        address _sushiFactory,
        address _uniswapV3Factory,
        address _balancerVault,
        address _wethAddress,
        bytes memory _primaryInitHash,
        bytes memory _secondaryInitHash
    )
        UniswapV2Swapper(
            _uniswapV2Factory,
            _sushiFactory,
            _primaryInitHash,
            _secondaryInitHash
        )
        UniswapV3Swapper(_uniswapV3Factory)
        CurveSwapper(_wethAddress)
    {
        if (_balancerVault == address(0)) revert InvalidInput();
        balancerVault = _balancerVault;
    }

    /** @notice Uses the dexId to route the swap to the correct DEX logic
        @dev Balancer's swap logic varies for single/multi swaps making it more complex to decode the input data
            hence the separate function called if id is 0x05 in zapFrom
        @param dexId The dexId of the DEX to be used
        @param fromAmount The amount of fromToken to be swapped
        @param swapPayload The payload for the swap - varies by DEX
        @return The amount of toToken received
     **/
    function _swap(
        bytes1 dexId,
        uint256 fromAmount,
        bytes calldata swapPayload
    ) internal returns (uint256) {
        if (dexId == 0x01) return _swapUniswapV2(0x01, fromAmount, swapPayload);
        else if (dexId == 0x02) return _swapUniswapV3(fromAmount, swapPayload);
        else if (dexId == 0x03)
            return _swapUniswapV2(0x02, fromAmount, swapPayload);
        else if (dexId == 0x04) return _swapWithCurve(swapPayload);
        else revert InvalidInput();
    }

    /** @notice Swaps using balancer vault
        @dev If the selector matches we know it's a single swap otherwise assume it's a multi swap
        @dev The negative delta int256 should be the amount of toToken received in a multi swap
        @param swapPayload The payload for the swap - varies by DEX
        @return The amount of toToken received
     **/
    function _swapBalancer(
        bytes calldata swapPayload
    ) internal returns (uint256) {
        (bool success, bytes memory data) = balancerVault.call(swapPayload);
        if (!success) revert FailedSwap();

        bytes4 selector = abi.decode(swapPayload, (bytes4));
        if (selector == bytes4(0x52bbbe29)) {
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
    }
}
