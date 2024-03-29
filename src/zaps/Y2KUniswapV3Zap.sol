// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {BytesLib} from "../libraries/BytesLib.sol";
import {IUniswapV3Pool} from "../interfaces/dexes/IUniswapV3Pool.sol";
import {IUniswapV3Callback} from "../interfaces/dexes/IUniswapV3Callback.sol";
import {IEarthquake} from "../interfaces/IEarthquake.sol";
import {IErrors} from "../interfaces/IErrors.sol";
import {ISignatureTransfer} from "../interfaces/ISignatureTransfer.sol";
import {IPermit2} from "../interfaces/IPermit2.sol";

/// @title UniswapV3 Zap for Y2K Vaults
/// @notice Tokens can be swapped on UniswapV3 and deposited into Y2K vaults
contract Y2KUniswapV3Zap is IErrors, IUniswapV3Callback, ISignatureTransfer {
    using SafeTransferLib for ERC20;
    using BytesLib for bytes;

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4295128740;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970341;
    bytes32 internal constant POOL_INIT_CODE_HASH =
        0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    address public immutable uniswapV3Factory;
    IPermit2 public immutable permit2;

    struct SwapInputs {
        address[] path;
        uint24[] fee;
        uint256 toAmountMin;
        uint256 id;
        address vaultAddress;
        address receiver;
    }

    /** @notice constructor
        @param _uniswapV3Factory The uniswapv3 factory address
        @param _permit2 The address of the permit2 contract
    **/
    constructor(address _uniswapV3Factory, address _permit2) {
        if (_uniswapV3Factory == address(0)) revert InvalidInput();
        if (_permit2 == address(0)) revert InvalidInput();
        uniswapV3Factory = _uniswapV3Factory;
        permit2 = IPermit2(_permit2);
    }

    /////////////////////////////////////////
    //        PUBLIC FUNCTIONS             //
    /////////////////////////////////////////
    /** @notice Swaps tokens on UniswapV3 and deposits them into a Y2K vault
        @param path The list of token address to swap between
        @param fee The list of fees to use for each swap
        @param fromAmount The amount of the fromToken to swap
        @param toAmountMin The minimum amount of the last token to receive
        @param id The id of the Y2K vault to deposit into
        @param vaultAddress The address of the Y2K vault to deposit into
        @param receiver The address to receive the Y2K vault shares
    **/
    function zapIn(
        address[] calldata path,
        uint24[] calldata fee,
        uint256 fromAmount,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress,
        address receiver
    ) external {
        ERC20(path[0]).safeTransferFrom(msg.sender, address(this), fromAmount);
        uint256 amountOut = _swap(path, fee, fromAmount);
        if (amountOut < toAmountMin) revert InvalidMinOut(amountOut);
        _deposit(path[path.length - 1], id, amountOut, vaultAddress, receiver);
    }

    /** @notice Swaps tokens on UniswapV3 using permit and deposits them into a Y2K vault
        @param inputs The swap inputs
        @param permit The permit struct for the token being permitted plus a nonce and deadline
        @param transferDetails Struct with recipient address and amount for transfer
        @param sig The signed permit message
    **/
    function zapInPermit(
        SwapInputs calldata inputs,
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) external {
        permit2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        uint256 amountOut = _swap(
            inputs.path,
            inputs.fee,
            transferDetails.requestedAmount
        );
        if (amountOut < inputs.toAmountMin) revert InvalidMinOut(amountOut);
        _deposit(
            inputs.path[inputs.path.length - 1],
            inputs.id,
            amountOut,
            inputs.vaultAddress,
            inputs.receiver
        );
    }

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
        (address tokenIn, uint24 fee, address tokenOut) = decodePool(_data);

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

    /** @notice Simulates the address for the pool of two tokens
        @param path An array of token addresses being swapped between
        @param fee An array of fees for the pools being swapped betwen
        @param fromAmount The amount of fromToken being swapped from
        @return amountOut The amount of toToken received
    **/
    function _swap(
        address[] calldata path,
        uint24[] calldata fee,
        uint256 fromAmount
    ) internal returns (uint256 amountOut) {
        if (path.length > 2) {
            amountOut = _executeSwap(path[0], path[1], fromAmount, fee[0]);
            for (uint256 i = 1; i < path.length - 2; ) {
                amountOut = _executeSwap(
                    path[i],
                    path[i + 1],
                    amountOut,
                    fee[i]
                );
                unchecked {
                    i++;
                }
            }
            return
                _executeSwap(
                    path[path.length - 2],
                    path[path.length - 1],
                    amountOut,
                    fee[path.length - 2]
                );
        } else {
            return _executeSwap(path[0], path[1], fromAmount, fee[0]);
        }
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
                    MIN_SQRT_RATIO,
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
                    MAX_SQRT_RATIO,
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
    ) private view returns (address pool) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            uniswapV3Factory,
                            keccak256(abi.encode(tokenA, tokenB, fee)),
                            POOL_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }

    /** @notice Decodes bytes to retrieve the fee and token addresses
        @param path The encoded data for fee and tokens
        @return tokenA - The address of the first token
        @return fee - The fee for the pool
        @return tokenB - The address of the second token
    **/
    function decodePool(
        bytes memory path
    ) internal pure returns (address tokenA, uint24 fee, address tokenB) {
        tokenA = path.toAddress(0);
        fee = path.toUint24(20);
        tokenB = path.toAddress(23);
    }
}
