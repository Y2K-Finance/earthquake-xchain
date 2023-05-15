// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IEarthQuakeVault {
    function controller() external view returns (address);

    function idEpochBegin(uint256 epoch) external view returns (uint256);
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
