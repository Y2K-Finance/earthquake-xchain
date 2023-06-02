// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {IBalancerVault} from "../interfaces/dexes/IBalancerVault.sol";
import {IEarthquake} from "../interfaces/IEarthquake.sol";
import {IErrors} from "../interfaces/IErrors.sol";

contract Y2KCallDataZap is IErrors {
    using SafeTransferLib for ERC20;
    address owner;
    address public immutable EARTHQUAKE_VAULT;

    mapping(address => bool) public whitelistedAddress;
    mapping(address => uint256) public routerId;

    constructor(address _earthquakeVault) {
        if (_earthquakeVault == address(0)) revert InvalidInput();
        EARTHQUAKE_VAULT = _earthquakeVault;
        owner = msg.sender;
    }

    function zapIn(
        ERC20 fromToken,
        ERC20 toToken,
        address destination,
        uint256 fromAmount,
        uint256 vaultId,
        bytes calldata inputData
    ) external payable {
        if (!whitelistedAddress[destination]) revert InvalidInput();
        fromToken.safeTransferFrom(msg.sender, address(this), fromAmount);
        fromToken.safeApprove(address(destination), fromAmount);

        (bool success, bytes memory outputData) = destination.call{
            value: msg.value
        }(inputData);
        if (!success) revert FailedCall(outputData);
        uint256 amountOut = _decodeData(outputData, routerId[destination]);
        toToken.safeApprove(EARTHQUAKE_VAULT, amountOut);
        IEarthquake(EARTHQUAKE_VAULT).deposit(vaultId, amountOut, msg.sender); // NOTE: Could take receiver input
    }

    function whitelistAddress(address routerAddress) external {
        if (msg.sender != owner) revert OnlyOwner();
        whitelistedAddress[routerAddress] = !whitelistedAddress[routerAddress];
    }

    // NOTE: This function could use the destination to decode the data
    function _decodeData(
        bytes memory outputData,
        uint256 id
    ) internal pure returns (uint256 outputAmount) {
        // NOTE: Need to check the id against the routes
        if (id == 0) return 0;
        // Or use storage variable to return function from the data
        return abi.decode(outputData, (uint256));
    }
}
