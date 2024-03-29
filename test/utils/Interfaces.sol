// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IStargateRouter {
    function factory() external view returns (address);

    function poolId() external view returns (uint16);
}

interface IvlY2K {
    function getAccount(
        address owner
    )
        external
        view
        returns (
            uint256 balance,
            uint256 lockEpochs,
            uint256 lastEpochPaid,
            uint256 rewards1,
            uint256 rewards2
        );
}

interface IBalancer {
    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }

    struct Funds {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

    function swap(
        SingleSwap memory singleSwap,
        Funds memory funds,
        uint256,
        uint256
    ) external payable returns (uint256);

    struct BatchSwapStep {
        bytes32 poolId;
        uint256 assetInIndex;
        uint256 assetOutIndex;
        uint256 amount;
        bytes userData;
    }

    function batchSwap(
        SwapKind kind,
        BatchSwapStep[] memory swaps,
        address[] memory assets,
        Funds memory funds,
        int256[] memory limits,
        uint256 deadline
    ) external payable returns (int256[] memory);
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
