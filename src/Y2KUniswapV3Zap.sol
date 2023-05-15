// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {BytesLib} from "./libraries/BytesLib.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Callback} from "./interfaces/IUniswapV3Callback.sol";
import {IEarthquake} from "./interfaces/IEarthquake.sol";
import {IErrors} from "./interfaces/IErrors.sol";

contract Y2KUniswapV3Zap is IErrors, IUniswapV3Callback {
    using SafeTransferLib for ERC20;
    using BytesLib for bytes;
    address public immutable UNISWAP_V3_FACTORY;
    address public immutable EARTHQUAKE_VAULT;
    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4295128740;

    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970341;
    bytes32 internal constant POOL_INIT_CODE_HASH =
        0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    constructor(address _uniswapV3Factory, address _earthquakeVault) {
        if (_uniswapV3Factory == address(0)) revert InvalidInput();
        if (_earthquakeVault == address(0)) revert InvalidInput();
        UNISWAP_V3_FACTORY = _uniswapV3Factory;
        EARTHQUAKE_VAULT = _earthquakeVault;
    }

    function zapIn(
        address[] calldata path,
        uint24[] calldata fee,
        uint256 fromAmount,
        uint256 toAmountMin,
        uint256 id
    ) external {
        ERC20(path[0]).safeTransferFrom(msg.sender, address(this), fromAmount);
        uint256 amountOut = _swapAndDeposit(path, fee, fromAmount);
        if (amountOut < toAmountMin) revert InvalidMinOut(amountOut);
        ERC20(path[path.length - 1]).safeApprove(EARTHQUAKE_VAULT, amountOut);
        IEarthquake(EARTHQUAKE_VAULT).deposit(id, amountOut, msg.sender); // NOTE: Could take receiver input
    }

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

    function _swapAndDeposit(
        address[] calldata path,
        uint24[] calldata fee,
        uint256 fromAmount
    ) internal returns (uint256 amountOut) {
        if (path.length > 2) {
            amountOut = _swap(path[0], path[1], fromAmount, fee[0]);
            uint256 swapLength = path.length - 2;
            for (uint256 i = 1; i < swapLength; ) {
                amountOut = _swap(path[i], path[i + 1], amountOut, fee[i]);
                unchecked {
                    i++;
                }
            }
            // NOTE: SwapLength is cached as path.length - 2 i.e. swapLength + 2 = path.length - 2 and swapLength + 1 = path.length - 1
            return
                _swap(
                    path[swapLength],
                    path[swapLength + 1],
                    amountOut,
                    fee[swapLength + 1]
                );
        } else {
            return _swap(path[0], path[1], fromAmount, fee[0]);
        }
    }

    function _swap(
        address tokenIn,
        address tokenOut,
        uint256 fromAmount,
        uint24 fee
    ) internal returns (uint256) {
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
    ) internal view returns (address pool) {
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
    ) internal pure returns (address tokenA, address tokenB, uint24 fee) {
        tokenA = path.toAddress(0);
        fee = path.toUint24(20);
        tokenB = path.toAddress(23);
    }
}
