// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {VaultController, IEarthquake} from "./controllers/vaultController.sol";
import {BridgeController} from "./controllers/bridgeController.sol";
import {BytesLib} from "../libraries/BytesLib.sol";
import {UniswapV3Swapper} from "./dexHelpers/uniswapV3Dest.sol";
import {UniswapV2Swapper} from "./dexHelpers/uniswapV2Dest.sol";

import {IStargateReceiver} from "../interfaces/bridges/IStargateReceiver.sol";
import {ILayerZeroReceiver} from "../interfaces/bridges/ILayerZeroReceiver.sol";
import {ERC1155Holder} from "lib/openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title Cross-chain bridge receiver for Y2K Vaults
/// @notice Transactions to Y2K bridge contracts on other chains relay to this contract to complete vault actions
contract ZapDest is
    Ownable,
    ERC1155Holder,
    VaultController,
    BridgeController,
    UniswapV2Swapper,
    UniswapV3Swapper,
    IStargateReceiver,
    ILayerZeroReceiver
{
    using BytesLib for bytes;
    address public immutable stargateRelayer;
    address public immutable stargateRelayerEth;
    address public immutable layerZeroRelayer;

    mapping(address => uint256) public addrCounter;
    mapping(uint16 => bytes) public trustedRemoteLookup;
    mapping(bytes1 => address) public idToExchange;
    mapping(address => uint256) public whitelistedVault;
    mapping(address => mapping(address => mapping(uint256 => uint256)))
        public receiverToVaultToIdToAmount;

    event ReceivedDeposit(address token, address receiver, uint256 amount);
    event ReceivedWithdrawal(
        bytes1 orderType,
        address receiver,
        uint256 amount
    );
    event TrustedRemoteAdded(
        uint16 chainId,
        bytes trustedAddress,
        address sender
    );
    event TokenToHopBridgeSet(
        address[] tokens,
        address[] bridges,
        address sender
    );
    event VaultWhitelisted(address vault, address sender);

    /** @notice constructor
        @dev Calls constructors for BridgeController, UniswapV2Swapper, and UniswapV3Swapper
        @param _stargateRelayer The address of the Stargate relayer on Arbitrum
        @param _stargateRelayerEth The address of the Stargate ETH relayer on Ethereum
        @param _layerZeroRelayer The address of the LayerZero relayer on Arbitrum
        @param _celerBridge The address of the Celer bridge on Arbitrum
        @param _hyphenBridge The address of the Hyphen bridge on Arbitrum
        @param _uniswapV2Factory The address of the Uniswap V2 factory on Arbitrum (fork)
        @param _sushiSwapFactory The address of the SushiSwap factory on Arbitrum (fork)
        @param _uniswapV3Factory The address of the Uniswap V3 factory on Arbitrum (fork)
        @param _sgEth The Stargate Eth address on Arbitrum
        @param _primaryInitHash The init code hash of the Uniswap V2 router on Arbitrum (fork)
        @param _secondaryInitHash The init code hash of the SushiSwap router on Arbitrum (fork)
     **/
    constructor(
        address _stargateRelayer,
        address _stargateRelayerEth,
        address _layerZeroRelayer,
        address _celerBridge,
        address _hyphenBridge,
        address _uniswapV2Factory,
        address _sushiSwapFactory,
        address _uniswapV3Factory,
        address _sgEth,
        bytes memory _primaryInitHash,
        bytes memory _secondaryInitHash
    )
        payable
        VaultController(_sgEth)
        BridgeController(_celerBridge, _hyphenBridge)
        UniswapV2Swapper(
            _uniswapV2Factory,
            _sushiSwapFactory,
            _primaryInitHash,
            _secondaryInitHash
        )
        UniswapV3Swapper(_uniswapV3Factory)
    {
        if (_stargateRelayer == address(0)) revert InvalidInput();
        if (_stargateRelayerEth == address(0)) revert InvalidInput();
        if (_layerZeroRelayer == address(0)) revert InvalidInput();
        stargateRelayer = _stargateRelayer;
        stargateRelayerEth = _stargateRelayerEth;
        layerZeroRelayer = _layerZeroRelayer;
    }

    //////////////////////////////////////////////
    //                 ADMIN                   //
    //////////////////////////////////////////////
    /** @notice Admin function to manage the Layerzero trusted addresses for withdrawals
        @param srcChainId The srcChainId as per LayerZero's classification
        @param trustedAddress The address of the LayerZero relayer
    **/
    function setTrustedRemoteLookup(
        uint16 srcChainId,
        bytes calldata trustedAddress
    ) external payable onlyOwner {
        if (keccak256(trustedAddress) == keccak256(bytes("")))
            revert InvalidInput();
        trustedRemoteLookup[srcChainId] = trustedAddress;
        emit TrustedRemoteAdded(srcChainId, trustedAddress, msg.sender);
    }

    /** @notice Admin function to manage the Hop bridges that can be used
        @param _tokens An array of ERC20 token addresses
        @param _bridges An array of Hop bridge addresses corresponding to each ERC20 token
    **/
    function setTokenToHopBridge(
        address[] calldata _tokens,
        address[] calldata _bridges
    ) external payable onlyOwner {
        if (_tokens.length != _bridges.length) revert InvalidInput();
        for (uint256 i = 0; i < _tokens.length; ) {
            tokenToHopBridge[_tokens[i]] = _bridges[i];
            unchecked {
                i++;
            }
        }
        emit TokenToHopBridgeSet(_tokens, _bridges, msg.sender);
    }

    /** @notice Admin function to manage the vaults the contract can deposit to
        @param _vaultAddress The address of the vault to whitelist on Y2K
    **/
    function whitelistVault(address _vaultAddress) external payable onlyOwner {
        if (_vaultAddress == address(0)) revert InvalidInput();
        whitelistedVault[_vaultAddress] = 1;
        emit VaultWhitelisted(_vaultAddress, msg.sender);
    }

    //////////////////////////////////////////////
    //                 PUBLIC                   //
    //////////////////////////////////////////////
    /** @notice Stargate relayer will invoke this function to bridge tokens with a payload
        @param _chainId The remote chainId sending the tokens
        @param _srcAddress The remote Bridge address
        @param _nonce The message ordering nonce
        @param _token The token contract on the local chain
        @param amountLD The qty of local _token contract tokens
        @param _payload The bytes containing the toAddress
    **/
    function sgReceive(
        uint16 _chainId,
        bytes memory _srcAddress,
        uint256 _nonce,
        address _token,
        uint256 amountLD,
        bytes calldata _payload
    ) external payable override {
        if (msg.sender != stargateRelayer && msg.sender != stargateRelayerEth)
            revert InvalidCaller();
        (address receiver, uint256 id, address vaultAddress) = abi.decode(
            _payload,
            (address, uint256, address)
        );

        if (id == 0) return _stageRefund(receiver, _token, amountLD);
        if (whitelistedVault[vaultAddress] != 1)
            return _stageRefund(receiver, _token, amountLD);
        // TODO: Hardcode address(this) as a constant
        bool success = _depositToVault(id, amountLD, _token, vaultAddress);
        if (!success) return _stageRefund(receiver, _token, amountLD);

        receiverToVaultToIdToAmount[receiver][vaultAddress][id] += amountLD;
        emit ReceivedDeposit(_token, address(this), amountLD);
    }

    /** @notice LayerZero endpoint will invoke this function to deliver the message on the destination
        @dev Payload is decoded to either withdraw, withdrawAndBridge, or withdrawSwapAndBridge
        @dev Bridging transactions are alway back to the calling chain
        @param _srcChainId - the source endpoint identifier
        @param _srcAddress - the source sending contract address from the source chain
        @param _nonce - the ordered message nonce
        @param _payload - the signed payload is the UA bytes has encoded to be sent
    **/
    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) external override {
        if (msg.sender != layerZeroRelayer) revert InvalidCaller();
        if (
            keccak256(_srcAddress) !=
            keccak256(trustedRemoteLookup[_srcChainId])
        ) revert InvalidCaller();

        (
            bytes1 funcSelector,
            bytes1 bridgeId,
            address receiver,
            uint256 id,
            address vaultAddress
        ) = abi.decode(_payload, (bytes1, bytes1, address, uint256, address));
        if (funcSelector == 0x00) revert InvalidFunctionId();

        _payload = _payload.length == 160
            ? bytes("")
            : _payload.sliceBytes(160, _payload.length - 160);

        _withdraw(
            funcSelector,
            bridgeId,
            receiver,
            id,
            _srcChainId,
            vaultAddress,
            _payload
        );
    }

    /** @notice Withdrawal function for the user to call on Arbitrum directly (without LayerZero relayer)
        @param funcSelector The function selector to toggle between withdrawal/withdrawAndBridge/WithdrawSwapAndBridge
        @param bridgeId The id for the bridge that should be used
        @param receiver The address of the receiver
        @param id The id for the epoch being withdraw from
        @param _srcChainId The srcChainId as per LayerZero's classification
        @param vaultAddress The address of the Y2K vault to withdraw from
        @param _withdrawPayload The payload containing information for swapping and bridging
    **/
    function withdraw(
        bytes1 funcSelector,
        bytes1 bridgeId,
        address receiver,
        uint256 id,
        uint16 _srcChainId,
        address vaultAddress,
        bytes memory _withdrawPayload
    ) external {
        if (msg.sender != receiver) revert InvalidCaller();
        _withdraw(
            funcSelector,
            bridgeId,
            receiver,
            id,
            _srcChainId,
            vaultAddress,
            _withdrawPayload
        );
    }

    /** @notice Refund tokens or eth to the original sender - only callable when an sgReceive tx fails
        @param token The origin token bridged (sgETH address used when bridged ETH)
        @param sender The original sender of the bridged tokens
    **/
    function claimRefund(address token, address sender) external {
        _claimRefund(sender, token);
    }

    //////////////////////////////////////////////
    //                 PRIVATE                  //
    //////////////////////////////////////////////
    /** @notice Executes withdrawal actions dependent on the function selector
        @dev If selector is 0x01 we can withdraw then return else we withdraw then checks if we should swap before bridging
        @dev Will use swapController and/or BridgeController when selector != 0x01
        @param funcSelector The function selector to toggle between withdrawal/withdrawAndBridge/WithdrawSwapAndBridge
        @param bridgeId The id for the bridge that should be used
        @param receiver The address of the receiver
        @param id The id for the epoch being withdraw from
        @param _srcChainId The srcChainId as per LayerZero's classification
        @param vaultAddress The address of the Y2K vault to withdraw from
        @param _payload The payload containing information for swapping and bridging
    **/
    function _withdraw(
        bytes1 funcSelector,
        bytes1 bridgeId,
        address receiver,
        uint256 id,
        uint16 _srcChainId,
        address vaultAddress,
        bytes memory _payload
    ) private {
        uint256 assets = receiverToVaultToIdToAmount[receiver][vaultAddress][
            id
        ];
        if (assets == 0) revert NullBalance();
        delete receiverToVaultToIdToAmount[receiver][vaultAddress][id];

        // NOTE: We check FS!=0x00 in sgReceive() and if FS==0x01 || FS<4 it would either be 0x01, 0x02, or 0x03
        if (funcSelector == 0x01)
            _withdrawFromVault(id, assets, receiver, vaultAddress);
        else if (uint8(funcSelector) < 4) {
            uint256 amountReceived = _withdrawFromVault(
                id,
                assets,
                address(this),
                vaultAddress
            );
            address asset = IEarthquake(vaultAddress).asset();
            if (funcSelector == 0x03)
                // NOTE: Re-using amountReceived for bridge input
                (asset, _payload, amountReceived) = _swapToBridgeToken(
                    amountReceived,
                    asset,
                    _payload
                );
            _bridgeToSource(
                bridgeId,
                receiver,
                asset,
                amountReceived,
                _srcChainId,
                _payload
            );
        } else revert InvalidFunctionId();
        emit ReceivedWithdrawal(funcSelector, receiver, assets);
    }

    /** @notice Swaps the fromToken to the token being bridged
        @dev The segment of the payload used is sliced leaving the payload for bridging
        @param swapAmount The amount of fromToken to swap
        @param token The address of the fromToken
        @param _payload The payload containing information for swapping
        @return amountOut The amount of toToken received from the swap
    **/
    function _swapToBridgeToken(
        uint256 swapAmount,
        address token,
        bytes memory _payload
    ) internal returns (address, bytes memory, uint256 amountOut) {
        (
            bytes1 swapId,
            uint256 toAmountMin,
            bytes1 dexId,
            address toToken
        ) = abi.decode(_payload, (bytes1, uint256, bytes1, address));

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = toToken;

        if (swapId == 0x01) {
            amountOut = _swapUniswapV2(
                dexId,
                swapAmount,
                path,
                toAmountMin // swapPayload
            );
            _payload = _payload.sliceBytes(128, _payload.length - 128);
        } else if (swapId == 0x02) {
            uint24[] memory fee = new uint24[](1);
            (, , , , fee[0]) = abi.decode(
                _payload,
                (bytes1, uint256, bytes1, address, uint24)
            );
            amountOut = _swapUniswapV3(swapAmount, path, fee, toAmountMin);
            _payload = _payload.sliceBytes(160, _payload.length - 160);
        } else revert InvalidSwapId();
        return (toToken, _payload, amountOut);
    }

    receive() external payable {}

    fallback() external payable {}
}
