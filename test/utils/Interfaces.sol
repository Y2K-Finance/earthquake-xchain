// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IStargateRouter {
    function factory() external view returns (address);

    function poolId() external view returns (uint16);
}

interface IEarthQuakeVault {
    function controller() external view returns (address);

    function idEpochBegin(uint256 epoch) external view returns (uint256);

    function endEpoch(uint256 id) external;

    function deposit(uint256 id, uint256 assets, address receiver) external;

    function previewWithdraw(
        uint256 id,
        uint256 assets
    ) external view returns (uint256 entitledAmount);
}

interface IEarthquakeController {
    function triggerEndEpoch(uint256 marketIndex, uint256 epochEnd) external;
}

interface IERC20 {
    function symbol() external view returns (string memory);

    function balanceOf(address account) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);
}

interface IERC1155 {
    function balanceOf(
        address account,
        uint256 id
    ) external view returns (uint256);
}

interface IPermit2 {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
