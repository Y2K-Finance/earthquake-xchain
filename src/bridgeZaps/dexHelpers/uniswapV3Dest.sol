// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {BytesLib} from "../../libraries/BytesLib.sol";
import {IUniswapV3Pool} from "../../interfaces/dexes/IUniswapV3Pool.sol";
import {IUniswapV3Callback} from "../../interfaces/dexes/IUniswapV3Callback.sol";
import {IEarthquake} from "../../interfaces/IEarthquake.sol";
import {IErrors} from "../../interfaces/IErrors.sol";

contract UniswapV3Swapper is IErrors, IUniswapV3Callback {
    using SafeTransferLib for ERC20;
    using BytesLib for bytes;
    address public immutable uniswapV3Factory;
    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant _MIN_SQRT_RATIO = 4295128740;

    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant _MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970341;
    bytes32 internal constant _POOL_INIT_CODE_HASH =
        0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    /** @notice constructor
        @param _uniswapV3Factory The uniswapv3 factory address
    **/
    constructor(address _uniswapV3Factory) {
        if (_uniswapV3Factory == address(0)) revert InvalidInput();
        uniswapV3Factory = _uniswapV3Factory;
    }

    /////////////////////////////////////////
    //        PUBLIC FUNCTIONS             //
    /////////////////////////////////////////
    /** @notice The callback implementation for UniswapV3 pools
        @param amount0Delta The amount of token0 received
        @param amount1Delta The amount of token1 received
        @param _data The encoded pool address, fee, and tokenOut address
    **/
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata _data
    ) external override {
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported
        (address tokenIn, address tokenOut, uint24 fee) = decodePool(_data);

        if (msg.sender != getPool(tokenIn, tokenOut, fee))
            revert InvalidCaller();

        SafeTransferLib.safeTransfer(
            ERC20(tokenIn),
            msg.sender,
            amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta)
        );
    }

    /////////////////////////////////////////
    //    INTERNAL & PRIVATE FUNCTIONS     //
    /////////////////////////////////////////
    /** @notice Decodes the payload and conducts the swaps
        @param fromAmount The amount of the fromToken being swapped
        @param path The path of tokens to swap between
        @param fee The fees for the pools being swapped between
        @param toAmountMin The minimum amount of the toToken to receive
        @return amountOut The amount of the toToken received
    **/
    function _swapUniswapV3(
        uint256 fromAmount,
        address[] memory path,
        uint24[] memory fee,
        uint256 toAmountMin
    ) internal returns (uint256 amountOut) {
        amountOut = _executeSwap(path[0], path[1], fromAmount, fee[0]);

        if (amountOut < toAmountMin) revert InvalidMinOut(amountOut);
    }

    /** @notice Executes the swap with the simulated V3 pool from tokenIn, tokenOut, and fee
        @param tokenIn The address of the fromToken
        @param tokenOut The address of the toToken
        @param fromAmount The amount of fromToken to swap
        @param fee The fee for the pool
        @return The amount of toToken received
    **/
    function _executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 fromAmount,
        uint24 fee
    ) private returns (uint256) {
        bool zeroForOne = tokenIn < tokenOut;

        if (zeroForOne) {
            (, int256 amountOut) = IUniswapV3Pool(
                getPool(tokenIn, tokenOut, fee)
            ).swap(
                    address(this),
                    zeroForOne,
                    int256(fromAmount),
                    _MIN_SQRT_RATIO,
                    abi.encodePacked(tokenIn, fee, tokenOut)
                );
            return uint256(-amountOut);
        } else {
            (int256 amountOut, ) = IUniswapV3Pool(
                getPool(tokenIn, tokenOut, fee)
            ).swap(
                    address(this),
                    zeroForOne,
                    int256(fromAmount),
                    _MAX_SQRT_RATIO,
                    abi.encodePacked(tokenIn, fee, tokenOut)
                );
            return uint256(-amountOut);
        }
    }

    /** @notice Simulates the address for the pool of two tokens
        @param tokenA The address of the first token
        @param tokenB The address of the second token
        @param fee The fee for the pool
        @return pool The address of the pool
    **/
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal view returns (address pool) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            uniswapV3Factory,
                            keccak256(abi.encode(tokenA, tokenB, fee)),
                            _POOL_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }

    /** @notice Decodes bytes to retrieve the fee and token addresses
        @param path The encoded data for fee and tokens
        @return tokenA tokenB fee
    **/
    function decodePool(
        bytes memory path
    ) internal pure returns (address tokenA, address tokenB, uint24 fee) {
        tokenA = path.toAddress(0);
        fee = path.toUint24(20);
        tokenB = path.toAddress(23);
    }
}
