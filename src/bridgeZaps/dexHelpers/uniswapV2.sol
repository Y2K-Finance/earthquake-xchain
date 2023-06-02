// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IUniswapPair} from "../../interfaces/dexes/IUniswapPair.sol";
import {IEarthquake} from "../../interfaces/IEarthquake.sol";
import {IErrors} from "../../interfaces/IErrors.sol";

contract UniswapV2Swapper is IErrors {
    using SafeTransferLib for ERC20;
    bytes public constant V2_INIT_HASH =
        hex"e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303";
    bytes public constant SUSHI_INIT_HASH =
        hex"e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303";
    address public immutable UNISWAP_V2_FORK_FACTORY;

    constructor(address _uniswapV2Factory) {
        if (_uniswapV2Factory == address(0)) revert InvalidInput();
        UNISWAP_V2_FORK_FACTORY = _uniswapV2Factory;
    }

    function _swapUniswapV2(
        bytes1 dexId,
        uint256 fromAmount,
        bytes calldata payload
    ) internal returns (uint256 amountOut) {
        (address[] memory path, uint256 toAmountMin) = abi.decode(
            payload,
            (address[], uint256)
        );
        uint256[] memory amounts = new uint256[](path.length - 1);
        address[] memory pairs = new address[](path.length - 1);

        // TODO:
        bytes memory initCodeHash;
        if (dexId == 0x01) initCodeHash = V2_INIT_HASH;
        else if (dexId == 0x02) initCodeHash = SUSHI_INIT_HASH;

        // TODO: More efficent way to use this amount?
        uint256 cachedFrom = fromAmount;

        for (uint256 i = 0; i < path.length - 1; ) {
            {
                address fromToken = path[i];
                address toToken = path[i + 1];

                pairs[i] = _getPair(fromToken, toToken, initCodeHash);
                (uint256 reserveA, uint256 reserveB, ) = IUniswapPair(pairs[i])
                    .getReserves();

                if (fromToken > toToken)
                    (reserveA, reserveB) = (reserveB, reserveA);

                amounts[i] =
                    ((cachedFrom * 997) * reserveB) /
                    ((reserveA * 1000) + (cachedFrom * 997));
                cachedFrom = amounts[i];
            }

            unchecked {
                i++;
            }
        }

        if (amounts[amounts.length - 1] < toAmountMin)
            revert InvalidMinOut(amounts[amounts.length - 1]);

        SafeTransferLib.safeTransfer(ERC20(path[0]), pairs[0], fromAmount);

        // NOTE: Abstract into it's own function
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

        amountOut = amounts[amounts.length - 1];
    }

    function _getPair(
        address tokenA,
        address tokenB,
        bytes memory initCodeHash
    ) internal view returns (address pair) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            UNISWAP_V2_FORK_FACTORY,
                            keccak256(abi.encodePacked(tokenA, tokenB)),
                            initCodeHash
                        )
                    )
                )
            )
        );
    }
}
