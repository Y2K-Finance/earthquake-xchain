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

    address public immutable UNISWAP_V3_FACTORY;
    IPermit2 public immutable PERMIT_2;

    constructor(address _uniswapV3Factory, address _permit2) {
        if (_uniswapV3Factory == address(0)) revert InvalidInput();
        if (_permit2 == address(0)) revert InvalidInput();
        UNISWAP_V3_FACTORY = _uniswapV3Factory;
        PERMIT_2 = IPermit2(_permit2);
    }

    /////////////////////////////////////////
    //        PUBLIC FUNCTIONS             //
    /////////////////////////////////////////
    function zapIn(
        address[] calldata path,
        uint24[] calldata fee,
        uint256 fromAmount,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress
    ) external {
        ERC20(path[0]).safeTransferFrom(msg.sender, address(this), fromAmount);
        uint256 amountOut = _swap(path, fee, fromAmount);
        if (amountOut < toAmountMin) revert InvalidMinOut(amountOut);
        _deposit(path[path.length - 1], id, amountOut, vaultAddress);
    }

    function zapInPermit(
        address[] calldata path,
        uint24[] calldata fee,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress,
        PermitTransferFrom memory permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) external {
        PERMIT_2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        uint256 amountOut = _swap(path, fee, transferDetails.requestedAmount);
        if (amountOut < toAmountMin) revert InvalidMinOut(amountOut);
        _deposit(path[path.length - 1], id, amountOut, vaultAddress);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata _data
    ) external override {
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported
        (address tokenIn, uint24 fee, address tokenOut) = decodePool(_data); // TODO: Check this is in correct order

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
    function _deposit(
        address fromToken,
        uint256 id,
        uint256 amountIn,
        address vaultAddress
    ) private {
        ERC20(fromToken).safeApprove(vaultAddress, amountIn);
        IEarthquake(vaultAddress).deposit(id, amountIn, msg.sender); // NOTE: Could take receiver input
    }

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
                            UNISWAP_V3_FACTORY,
                            keccak256(abi.encode(tokenA, tokenB, fee)),
                            POOL_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }

    function decodePool(
        bytes memory path
    ) internal pure returns (address tokenA, uint24 fee, address tokenB) {
        tokenA = path.toAddress(0);
        fee = path.toUint24(20);
        tokenB = path.toAddress(23);
    }
}
