// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {ICelerBridge} from "../../interfaces/bridges/ICelerBridge.sol";
import {IHyphenBridge} from "../../interfaces/bridges/IHyphenBridge.sol";
import {IConnextBridge} from "../../interfaces/bridges/IConnextBridge.sol";
import {IErrors} from "../../interfaces/IErrors.sol";

abstract contract BridgeController is IErrors {
    using SafeTransferLib for ERC20;
    ICelerBridge public immutable CELER_BRIDGE;
    IHyphenBridge public immutable HYPHEN_BRIDGE;
    IConnextBridge public immutable CONNEXT_BRIDGE;

    // TODO: Check the destinationDomain isn't just the chainId
    mapping(uint256 => uint32) public chainIdToDomain;

    constructor(
        address _celerBridge,
        address _hyphenBridge,
        address _connextBridge
    ) {
        if (_celerBridge == address(0)) revert InvalidInput();
        if (_hyphenBridge == address(0)) revert InvalidInput();
        if (_connextBridge == address(0)) revert InvalidInput();

        CELER_BRIDGE = ICelerBridge(_celerBridge);
        HYPHEN_BRIDGE = IHyphenBridge(_hyphenBridge);
        CONNEXT_BRIDGE = IConnextBridge(_connextBridge);
    }

    //////////////////////////////////////////////
    //                 PUBLIC                    //
    //////////////////////////////////////////////

    //////////////////////////////////////////////
    //                 INTERNAL                 //
    //////////////////////////////////////////////
    function _bridgeToSource(
        bytes1 _bridgeId,
        address _receiver,
        address _token,
        uint256 _shares,
        uint16 _sourceChainId
    ) internal {
        // TODO: change maxSlippage input for Celer to an input deconstructed
        uint256 maxSlippage = 1e6;
        if (_bridgeId == 0x01)
            _bridgeWithCeler(
                _receiver,
                _token,
                _shares,
                _sourceChainId,
                maxSlippage
            );
        else if (_bridgeId == 0x02)
            _bridgeWithHyphen(_receiver, _token, _shares, _sourceChainId);
        else if (_bridgeId == 0x03)
            _bridgeWithConnext(
                _receiver,
                _token,
                _shares,
                _sourceChainId,
                maxSlippage
            );
        else revert InvalidInput();
    }

    function _bridgeWithCeler(
        address _receiver,
        address _token,
        uint256 _amount,
        uint16 _dstChainId,
        uint256 maxSlippage
    ) internal {
        ERC20(_token).safeApprove(address(CELER_BRIDGE), _amount);
        CELER_BRIDGE.send(
            _receiver,
            _token,
            _amount,
            _dstChainId,
            uint64(block.timestamp),
            uint32(maxSlippage)
        );
    }

    function _bridgeWithHyphen(
        address _receiver,
        address _token,
        uint256 _amount,
        uint16 _srcChainId
    ) internal {
        ERC20(_token).safeApprove(address(HYPHEN_BRIDGE), _amount);
        HYPHEN_BRIDGE.depositErc20(
            _srcChainId,
            _token,
            _receiver,
            _amount,
            "Y2K"
        );
    }

    function _bridgeWithConnext(
        address _receiver,
        address _token,
        uint256 _amount,
        uint16 _srcChainId,
        uint256 maxSlippage
    ) internal {
        // TODO: domain fetched and checked if not same as srcId
        ERC20(_token).safeApprove(address(CONNEXT_BRIDGE), _amount);

        // TODO: Relayer feed source
        uint256 relayerFee = 0;
        CONNEXT_BRIDGE.xcall{value: relayerFee}(
            _srcChainId, // _destination: Domain ID of the destination chain
            _receiver,
            _token,
            msg.sender, // TODO: _delegate: address that can revert or forceLocal on destination
            _amount,
            maxSlippage,
            bytes("") // _callData: empty bytes because we're only sending funds
        );
    }

    function bridgeWithHop() internal {}
}
