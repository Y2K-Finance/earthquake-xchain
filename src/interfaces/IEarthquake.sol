pragma solidity 0.8.18;

interface IEarthquake {
    function deposit(uint256 pid, uint256 amount, address to) external;

    function depositETH(uint256 pid, address to) external payable;
}
