// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {FxBaseChildTunnel} from "../../lib/fx-portal/contracts/tunnel/FxBaseChildTunnel.sol";
import {IERC20} from "../interfaces/IERC20.sol";

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Zero value when it has to be different from zero.
error ZeroValue();

/// @dev Failure of a transfer.
/// @param token Address of a token.
/// @param from Address `from`.
/// @param to Address `to`.
/// @param amount Token amount.
error TransferFailed(address token, address from, address to, uint256 amount);

/// @title FxERC20ChildTunnel - Smart contract for the L2 token management part
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract FxERC20ChildTunnel is FxBaseChildTunnel {
    event FxDepositERC20(address indexed childToken, address indexed rootToken, address from, address indexed to, uint256 amount);
    event FxWithdrawERC20(address indexed rootToken, address indexed childToken, address from, address indexed to, uint256 amount);

    // Child token address
    address public immutable childToken;
    // Root token address
    address public immutable rootToken;

    /// @dev FxERC20ChildTunnel constructor.
    /// @param _fxChild Fx Child contract address.
    /// @param _childToken L2 token address.
    /// @param _rootToken Corresponding L1 token address.
    constructor(address _fxChild, address _childToken, address _rootToken) FxBaseChildTunnel(_fxChild) {
        // Check for zero addresses
        if (_fxChild == address(0) || _childToken == address(0) || _rootToken == address(0)) {
            revert ZeroAddress();
        }

        childToken = _childToken;
        rootToken = _rootToken;
    }

    /// @dev Deposits tokens on L2 in order to obtain their corresponding bridged version on L1.
    /// @notice Destination address is the same as the sender address.
    /// @param amount Token amount to be deposited.
    function deposit(uint256 amount) external {
        _deposit(msg.sender, amount);
    }

    /// @dev Deposits tokens on L2 in order to obtain their corresponding bridged version on L1 by a specified address.
    /// @param to Destination address on L1.
    /// @param amount Token amount to be deposited.
    function depositTo(address to, uint256 amount) external {
        // Check for the address to deposit tokens to
        if (to == address(0)) {
            revert ZeroAddress();
        }

        _deposit(to, amount);
    }

    /// @dev Receives the token message from L1 and transfers L2 tokens to a specified address.
    /// @notice Reentrancy is not possible as tokens are verified before the contract deployment.
    /// @param sender FxERC20RootTunnel contract address from L1.
    /// @param message Incoming bridge message.
    function _processMessageFromRoot(
        uint256 /* stateId */,
        address sender,
        bytes memory message
    ) internal override validateSender(sender) {
        // Decode incoming message from root: (address, address, uint256)
        (address from, address to, uint256 amount) = abi.decode(message, (address, address, uint256));

        // Transfer decoded amount of tokens to a specified address
        bool success = IERC20(childToken).transfer(to, amount);
        if (!success) {
            revert TransferFailed(childToken, address(this), to, amount);
        }

        emit FxWithdrawERC20(rootToken, childToken, from, to, amount);
    }

    /// @dev Deposits tokens on L2 to get their representation on L1 by a specified address.
    /// @param to Destination address on L1.
    /// @param amount Token amount to be deposited.
    function _deposit(address to, uint256 amount) internal {
        // Check for the non-zero amount
        if (amount == 0) {
            revert ZeroValue();
        }

        // Encode message for root: (address, address, uint256)
        bytes memory message = abi.encode(msg.sender, to, amount);
        // Send message to root
        _sendMessageToRoot(message);

        // Deposit tokens on an L2 bridge contract (lock)
        bool success = IERC20(childToken).transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert TransferFailed(childToken, msg.sender, address(this), amount);
        }

        emit FxDepositERC20(childToken, rootToken, msg.sender, to, amount);
    }
}
