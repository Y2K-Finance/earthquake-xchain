// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IUniswapPair} from "../../interfaces/dexes/IUniswapPair.sol";
import {IEarthquake} from "../../interfaces/IEarthquake.sol";
import {IErrors} from "../../interfaces/IErrors.sol";

import "forge-std/console.sol";

contract UniswapV2Swapper is IErrors {
    using SafeTransferLib for ERC20;
    // TODO: The INITs should be inputs
    bytes public constant PRIMARY_INIT_HASH =
        hex"a856464ae65f7619087bc369daaf7e387dae1e5af69cfa7935850ebf754b04c1";
    bytes public constant SECONDARY_INIT_HASH =
        hex"e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303";
    address public immutable uniswapV2ForkFactory;
    address public immutable sushiFactory;

    constructor(address _uniswapV2Factory, address _sushiFactory) {
        if (_uniswapV2Factory == address(0)) revert InvalidInput();
        if (_sushiFactory == address(0)) revert InvalidInput();
        uniswapV2ForkFactory = _uniswapV2Factory;
        sushiFactory = _sushiFactory;
    }

    function _swapUniswapV2(
        bytes1 dexId,
        uint256 fromAmount,
        bytes memory payload
    ) internal returns (uint256 amountOut) {
        (address[] memory path, uint256 toAmountMin) = abi.decode(
            payload,
            (address[], uint256)
        );
        console.logUint(path.length);
        console.logAddress(path[0]);
        console.logAddress(path[1]);
        uint256[] memory amounts = new uint256[](path.length - 1);
        address[] memory pairs = new address[](path.length - 1);

        bytes memory initCodeHash;
        address factory;
        if (dexId == 0x01) {
            initCodeHash = PRIMARY_INIT_HASH;
            factory = uniswapV2ForkFactory;
        } else if (dexId == 0x02) {
            initCodeHash = SECONDARY_INIT_HASH;
            factory = sushiFactory;
        }

        // TODO: More efficent way to use this amount?
        uint256 cachedFrom = fromAmount;

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
