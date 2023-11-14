// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {FxBaseRootTunnel} from "../../lib/fx-portal/contracts/tunnel/FxBaseRootTunnel.sol";
import {IERC20} from "../interfaces/IERC20.sol";

/**
 * @title FxERC20RootTunnel
 */
contract FxERC20RootTunnel is FxBaseRootTunnel {
    event FxDepositERC20(address indexed childToken, address indexed rootToken, address from, address indexed to, uint256 amount);
    event FxWithdrawERC20(address indexed rootToken, address indexed childToken, address from, address indexed to, uint256 amount);

    // Child token
    address public immutable childToken;
    // Root token
    address public immutable rootToken;

    constructor(address _checkpointManager, address _fxRoot, address _childToken, address _rootToken)
        FxBaseRootTunnel(_checkpointManager, _fxRoot)
    {
        childToken = _childToken;
        rootToken = _rootToken;
    }

    function withdraw(address to, uint256 amount) external {
        // Transfer from sender to this contract
        IERC20(rootToken).transferFrom(msg.sender, address(this), amount);

        // Burn tokens
        IERC20(rootToken).burn(amount);

        // Send message to child
        bytes memory message = abi.encode(msg.sender, to, amount);
        _sendMessageToChild(message);
        emit FxWithdrawERC20(rootToken, childToken, msg.sender, to, amount);
    }

    // exit processor
    function _processMessageFromChild(bytes memory data) internal override {
        // Decode message from child
        (address from, address to, uint256 amount) = abi.decode(data, (address, address, uint256));

        // transfer from tokens to
        IERC20(rootToken).mint(to, amount);
        emit FxDepositERC20(childToken, rootToken, from, to, amount);
    }
}
