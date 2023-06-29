// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapPair} from "../interfaces/dexes/IUniswapPair.sol";
import {IEarthquake} from "../interfaces/IEarthquake.sol";
import {IErrors} from "../interfaces/IErrors.sol";

import {ILBPair} from "../interfaces/dexes/ILBPair.sol";
import {ILBLegacyPair} from "../interfaces/dexes/ILBLegacyPair.sol";
import {ILBFactory} from "../interfaces/dexes/ILBFactory.sol";
import {ILBLegacyFactory} from "../interfaces/dexes/ILBLegacyFactory.sol";
import {IJoeFactory} from "../interfaces/dexes/IJoeFactory.sol";
import {PackedUint128Math} from "../libraries/PackedUint128Math.sol";

import {console2 as console} from "lib/forge-std/src/console2.sol";

contract Y2KTraderJoeZap is IErrors {
    using SafeERC20 for IERC20;
    using PackedUint128Math for bytes32;

    ILBLegacyFactory public immutable LEGACY_FACTORY;
    ILBFactory public immutable FACTORY;
    IJoeFactory public immutable FACTORY_V1;

    error InvalidPair(address tokenX, address tokenY, uint256 binStep);

    /**
     * @dev The path parameters, such as:
     * - pairBinSteps: The list of bin steps of the pairs to go through
     * - versions: The list of versions of the pairs to go through
     * - tokenPath: The list of tokens in the path to go through
     */
    struct Path {
        uint256[] pairBinSteps;
        Version[] versions;
        IERC20[] tokenPath;
    }
    /**
     * @dev This enum represents the version of the pair requested
     * - V1: Joe V1 pair
     * - V2: LB pair V2. Also called legacyPair
     * - V2_1: LB pair V2.1 (current version)
     */
    enum Version {
        V1,
        V2,
        V2_1
    }

    constructor(address legacyFactory, address factory, address factoryV1) {
        if (legacyFactory == address(0)) revert InvalidInput();
        if (factory == address(0)) revert InvalidInput();
        if (factoryV1 == address(0)) revert InvalidInput();
        LEGACY_FACTORY = ILBLegacyFactory(legacyFactory);
        FACTORY = ILBFactory(factory);
        FACTORY_V1 = IJoeFactory(factoryV1);
    }

    function zapIn(
        Path calldata path,
        uint256 fromAmount,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress,
        address receiver
    ) external {
        address[] memory pairs = _getPairs(
            path.pairBinSteps,
            path.versions,
            path.tokenPath
        );
        path.tokenPath[0].safeTransferFrom(msg.sender, pairs[0], fromAmount);
        uint256 amountOut = _swap(
            pairs,
            path.tokenPath,
            path.versions,
            fromAmount
        );
        if (amountOut < toAmountMin) revert InvalidMinOut(amountOut);
        path.tokenPath[path.tokenPath.length - 1].safeApprove(
            vaultAddress,
            amountOut
        );
        IEarthquake(vaultAddress).deposit(id, amountOut, receiver); // NOTE: Could take receiver input
    }

    function _swap(
        address[] memory pairs,
        IERC20[] calldata path,
        Version[] calldata versions,
        uint256 fromAmount
    ) internal returns (uint256 amountOut) {
        Version version;
        address pair;
        uint256 pathLength = path.length - 1;

        IERC20 fromToken;
        IERC20 toToken = path[0];

        for (uint256 i = 0; i < pathLength; ) {
            pair = pairs[i];
            version = versions[i];
            fromToken = toToken;
            toToken = path[i + 1];

            if (version == Version.V1) {
                (uint256 reserveA, uint256 reserveB, ) = IUniswapPair(pairs[i])
                    .getReserves();
                bool zeroForOne = fromToken < toToken;

                if (!zeroForOne) (reserveA, reserveB) = (reserveB, reserveA);
                amountOut =
                    ((fromAmount * 997) * reserveB) /
                    ((reserveA * 1000) + (fromAmount * 997));

                if (zeroForOne)
                    IUniswapPair(pair).swap(0, amountOut, address(this), "");
                else IUniswapPair(pair).swap(amountOut, 0, address(this), "");
            } else if (version == Version.V2) {
                bool swapForY = toToken == ILBLegacyPair(pair).tokenY();
                (uint256 amountXOut, uint256 amountYOut) = ILBLegacyPair(pair)
                    .swap(swapForY, address(this));

                if (swapForY) amountOut = amountYOut;
                else amountOut = amountXOut;
            } else {
                bool swapForY = toToken == ILBPair(pair).getTokenY();
                (uint256 amountXOut, uint256 amountYOut) = ILBPair(pair)
                    .swap(swapForY, address(this))
                    .decode();

                if (swapForY) amountOut = amountYOut;
                else amountOut = amountXOut;
            }
            unchecked {
                i++;
            }
        }
    }

    function _getPairs(
        uint256[] calldata pairBinSteps,
        Version[] calldata versions,
        IERC20[] calldata path
    ) internal view returns (address[] memory pairs) {
        pairs = new address[](pairBinSteps.length);
        IERC20 fromToken;
        IERC20 toToken = path[0];

        unchecked {
            for (uint256 i; i < pairs.length; ++i) {
                fromToken = toToken;
                toToken = path[i + 1];

                pairs[i] = _getPair(
                    fromToken,
                    toToken,
                    pairBinSteps[i],
                    versions[i]
                );
            }
        }
    }

    function _getPair(
        IERC20 tokenX,
        IERC20 tokenY,
        uint256 binStep,
        Version version
    ) private view returns (address pair) {
        if (version == Version.V1) {
            pair = FACTORY_V1.getPair(address(tokenX), address(tokenY));
            if (pair == address(0))
                revert InvalidPair(address(tokenX), address(tokenY), binStep);
        } else {
            pair = address(
                _getLBPairInformation(tokenX, tokenY, binStep, version)
            );
        }
    }

    /**
     * @notice Helper function to return the address of the LBPair
     * @dev Revert if the pair is not created yet
     * @param tokenX The address of the tokenX
     * @param tokenY The address of the tokenY
     * @param binStep The bin step of the LBPair
     * @param version The version of the LBPair
     * @return lbPair The address of the LBPair
     */
    function _getLBPairInformation(
        IERC20 tokenX,
        IERC20 tokenY,
        uint256 binStep,
        Version version
    ) private view returns (address lbPair) {
        if (version == Version.V2) {
            lbPair = address(
                LEGACY_FACTORY
                    .getLBPairInformation(tokenX, tokenY, binStep)
                    .LBPair
            );
        } else {
            lbPair = address(
                FACTORY.getLBPairInformation(tokenX, tokenY, binStep).LBPair
            );
        }

        if (lbPair == address(0)) {
            revert InvalidPair(address(tokenX), address(tokenY), binStep);
        }
    }
}
