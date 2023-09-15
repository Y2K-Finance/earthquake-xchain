// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IUniswapPair} from "../../interfaces/dexes/IUniswapPair.sol";
import {IEarthquake} from "../../interfaces/IEarthquake.sol";
import {IErrors} from "../../interfaces/IErrors.sol";

contract UniswapV2Swapper is IErrors {
    using SafeTransferLib for ERC20;
    address public immutable uniswapV2ForkFactory;
    address public immutable sushiFactory;
    bytes internal primaryInitHash;
    bytes internal secondaryInitHash;

    /** @notice constructor
        @param _uniswapV2Factory The uniswapV2 factory address - as deployed on mainnet
        @param _sushiFactory The sushiswap factory address
        @param _primaryInitHash The init code hash for uniswapV2
        @param _secondaryInitHash The init code hash for sushiSwap fork
    **/
    constructor(
        address _uniswapV2Factory,
        address _sushiFactory,
        bytes memory _primaryInitHash,
        bytes memory _secondaryInitHash
    ) {
        if (_uniswapV2Factory == address(0)) revert InvalidInput();
        if (_sushiFactory == address(0)) revert InvalidInput();
        if (keccak256(_primaryInitHash) == keccak256(bytes("")))
            revert InvalidInput();
        if (keccak256(_secondaryInitHash) == keccak256(bytes("")))
            revert InvalidInput();

        uniswapV2ForkFactory = _uniswapV2Factory;
        sushiFactory = _sushiFactory;
        primaryInitHash = _primaryInitHash;
        secondaryInitHash = _secondaryInitHash;
    }

    /** @notice Decodes the payload and conducts the swaps
        @dev The dex id lets us select the initCodeHash and factory used to simulate pair addresses
        @param dexId The id for the DEX being used (0x01 for uniswapV2, 0x02 for sushiSwap)
        @param fromAmount The amount of the fromToken being swapped
        @param path The path of tokens to swap between
        @param toAmountMin The minimum amount of the toToken to receive
        @return amountOut The amount of the toToken received
    **/
    function _swapUniswapV2(
        bytes1 dexId,
        uint256 fromAmount,
        address[] memory path,
        uint256 toAmountMin
    ) internal returns (uint256 amountOut) {
        bytes memory initCodeHash;
        address factory;
        if (dexId == 0x01) {
            initCodeHash = primaryInitHash;
            factory = uniswapV2ForkFactory;
        } else if (dexId == 0x02) {
            initCodeHash = secondaryInitHash;
            factory = sushiFactory;
        }

        amountOut = fromAmount;
        address fromToken = path[0];
        address toToken = path[1];

        address pair = _getPair(fromToken, toToken, initCodeHash, factory);
        (uint256 reserveA, uint256 reserveB, ) = IUniswapPair(pair)
            .getReserves();
        if (fromToken > toToken) (reserveA, reserveB) = (reserveB, reserveA);

        amountOut =
            ((amountOut * 997) * reserveB) /
            ((reserveA * 1000) + (amountOut * 997));
        if (amountOut < toAmountMin) revert InvalidMinOut(amountOut);

        SafeTransferLib.safeTransfer(ERC20(path[0]), pair, fromAmount);

        bool zeroForOne = path[0] < path[1];
        IUniswapPair(pair).swap(
            zeroForOne ? 0 : amountOut,
            zeroForOne ? amountOut : 0,
            address(this),
            ""
        );
    }

    /** @notice Simulates the address for the pair of two tokens
        @param tokenA The address of the first token
        @param tokenB The address of the second token
        @param initCodeHash The init code hash for selected DEX
        @param factory The address of the factory being used
        @return pair The address of the pair
    **/
    function _getPair(
        address tokenA,
        address tokenB,
        bytes memory initCodeHash,
        address factory
    ) internal pure returns (address pair) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encodePacked(tokenA, tokenB)),
                            initCodeHash
                        )
                    )
                )
            )
        );
    }
}
