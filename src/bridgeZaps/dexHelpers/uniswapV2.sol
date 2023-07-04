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
        @param payload The encoded payload for the swap - abi.encode(address[] path, uint256 minAmountOut)
        @return amountOut The amount of the toToken received
    **/
    function _swapUniswapV2(
        bytes1 dexId,
        uint256 fromAmount,
        bytes memory payload
    ) internal returns (uint256 amountOut) {
        (address[] memory path, uint256 toAmountMin) = abi.decode(
            payload,
            (address[], uint256)
        );
        uint256[] memory amounts = new uint256[](path.length - 1);
        address[] memory pairs = new address[](path.length - 1);

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
        for (uint256 i = 0; i < path.length - 1; ) {
            {
                address fromToken = path[i];
                address toToken = path[i + 1];

                pairs[i] = _getPair(fromToken, toToken, initCodeHash, factory);
                (uint256 reserveA, uint256 reserveB, ) = IUniswapPair(pairs[i])
                    .getReserves();

                if (fromToken > toToken)
                    (reserveA, reserveB) = (reserveB, reserveA);

                amounts[i] =
                    ((amountOut * 997) * reserveB) /
                    ((reserveA * 1000) + (amountOut * 997));
                amountOut = amounts[i];
            }

            unchecked {
                i++;
            }
        }

        if (amounts[amounts.length - 1] < toAmountMin)
            revert InvalidMinOut(amounts[amounts.length - 1]);

        SafeTransferLib.safeTransfer(ERC20(path[0]), pairs[0], fromAmount);

        return _executeSwap(path, pairs, amounts);
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

    /** @notice Executes swaps on UniswapV2 fork
        @param path The array of token addresses to swap between
        @param pairs The array of pairs to swap through
        @param amounts The array of amounts to swap with each pair 
        @return The amount of destination token being received
    **/
    function _executeSwap(
        address[] memory path,
        address[] memory pairs,
        uint256[] memory amounts
    ) internal returns (uint256) {
        bool zeroForOne = path[0] < path[1];
        if (pairs.length > 1) {
            IUniswapPair(pairs[0]).swap(
                zeroForOne ? 0 : amounts[0],
                zeroForOne ? amounts[0] : 0,
                pairs[1],
                ""
            );
            for (uint256 i = 1; i < pairs.length - 1; ) {
                zeroForOne = path[i] < path[i + 1];
                IUniswapPair(pairs[i]).swap(
                    zeroForOne ? 0 : amounts[i],
                    zeroForOne ? amounts[i] : 0,
                    pairs[i + 1],
                    ""
                );
                unchecked {
                    i++;
                }
            }
            zeroForOne = path[path.length - 2] < path[path.length - 1];
            IUniswapPair(pairs[pairs.length - 1]).swap(
                zeroForOne ? 0 : amounts[pairs.length - 1],
                zeroForOne ? amounts[pairs.length - 1] : 0,
                address(this),
                ""
            );
        } else {
            IUniswapPair(pairs[0]).swap(
                zeroForOne ? 0 : amounts[0],
                zeroForOne ? amounts[0] : 0,
                address(this),
                ""
            );
        }

        return amounts[amounts.length - 1];
    }
}
