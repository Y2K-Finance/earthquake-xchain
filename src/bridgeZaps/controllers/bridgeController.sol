// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {ICelerBridge} from "../../interfaces/bridges/ICelerBridge.sol";
import {IHyphenBridge} from "../../interfaces/bridges/IHyphenBridge.sol";
import {IHopBridge} from "../../interfaces/bridges/IHopBridge.sol";
import {IErrors} from "../../interfaces/IErrors.sol";

import "forge-std/console.sol";

abstract contract BridgeController is IErrors {
    using SafeTransferLib for ERC20;
    ICelerBridge public immutable celerBridge;
    IHyphenBridge public immutable hyphenBridge;

    // TODO: Check the destinationDomain isn't just the chainId
    mapping(uint256 => uint32) public chainIdToDomain;
    mapping(address => address) public tokenToHopBridge;

    constructor(address _celerBridge, address _hyphenBridge) {
        if (_celerBridge == address(0)) revert InvalidInput();
        if (_hyphenBridge == address(0)) revert InvalidInput();

        celerBridge = ICelerBridge(_celerBridge);
        hyphenBridge = IHyphenBridge(_hyphenBridge);
    }

    //////////////////////////////////////////////
    //                 INTERNAL                 //
    //////////////////////////////////////////////
    function _bridgeToSource(
        bytes1 _bridgeId,
        address _receiver,
        address _token,
        uint256 _amount,
        uint16 _sourceChainId,
        bytes memory _withdrawPayload
    ) internal {
        if (_bridgeId == 0x01) {
            uint256 maxSlippage = abi.decode(_withdrawPayload, (uint256));
            console.logUint(maxSlippage);
            _bridgeWithCeler(
                _receiver,
                _token,
                _amount,
                _sourceChainId,
                maxSlippage
            );
        } else if (_bridgeId == 0x02)
            _bridgeWithHyphen(_receiver, _token, _amount, _sourceChainId);
        else if (_bridgeId == 0x03) {
            (uint256 maxSlippage, uint256 bonderFee) = abi.decode(
                _withdrawPayload,
                (uint256, uint256)
            );
            _bridgeWithHop(
                _receiver,
                _token,
                _amount,
                _sourceChainId,
                maxSlippage,
                bonderFee
            );
        } else revert InvalidBridgeId();
    }

    function _bridgeWithCeler(
        address _receiver,
        address _token,
        uint256 _amount,
        uint16 _dstChainId,
        uint256 maxSlippage
    ) internal {
        ERC20(_token).safeApprove(address(celerBridge), _amount);
        celerBridge.send(
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
        ERC20(_token).safeApprove(address(hyphenBridge), _amount);
        hyphenBridge.depositErc20(
            _srcChainId,
            _token,
            _receiver,
            _amount,
            "Y2K"
        );
    }

    // maxSlippage input of 100 would be 1% slippage
    function _bridgeWithHop(
        address _receiver,
        address _token,
        uint256 _amount,
        uint16 _srcChainId,
        uint256 maxSlippage,
        uint256 bonderFee
    ) internal {
        uint256 amountOutMin = (_amount * (10000 - maxSlippage)) / 10000;
        uint256 deadline = block.timestamp + 2700;
        address bridgeAddress = tokenToHopBridge[_token];
        ERC20(_token).safeApprove(bridgeAddress, _amount);

        IHopBridge(bridgeAddress).swapAndSend(
            _srcChainId, // _destination: Domain ID of the destination chain
            _receiver,
            _amount,
            bonderFee,
            amountOutMin,
            deadline,
            (amountOutMin * 998) / 1000, // Adding extra slippage for cross-chain tx
            deadline
        );
    }
}
