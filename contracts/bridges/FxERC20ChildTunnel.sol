// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {FxBaseChildTunnel} from "../../lib/fx-portal/contracts/tunnel/FxBaseChildTunnel.sol";
import {IERC20} from "../interfaces/IERC20.sol";

/**
 * @title FxERC20ChildTunnel
 */
contract FxERC20ChildTunnel is FxBaseChildTunnel {
    event FxDepositERC20(address indexed childToken, address indexed rootToken, address from, address indexed to, uint256 amount);
    event FxWithdrawERC20(address indexed rootToken, address indexed childToken, address from, address indexed to, uint256 amount);

    // Child token
    address public immutable childToken;
    // Root token
    address public immutable rootToken;

    // slither-disable-next-line missing-zero-check
    constructor(address _fxChild, address _childToken, address _rootToken) FxBaseChildTunnel(_fxChild) {
        childToken = _childToken;
        rootToken = _rootToken;
    }

    function deposit(uint256 amount) external {
        _deposit(msg.sender, amount);
    }

    function depositTo(address to, uint256 amount) external {
        _deposit(to, amount);
    }

    function _processMessageFromRoot(
        uint256 /* stateId */,
        address sender,
        bytes memory data
    ) internal override validateSender(sender) {
        // Decode incoming data
        (address from, address to, uint256 amount) = abi.decode(data, (address, address, uint256));

        // Transfer tokens
        IERC20(childToken).transfer(to, amount);

        emit FxWithdrawERC20(rootToken, childToken, from, to, amount);
    }

    function _deposit(address to, uint256 amount) internal {
        // Deposit tokens
        IERC20(childToken).transferFrom(msg.sender, address(this), amount);

        // Send message to root
        bytes memory message = abi.encode(msg.sender, to, amount);
        _sendMessageToRoot(message);

        emit FxDepositERC20(childToken, rootToken, msg.sender, to, amount);
    }
}
