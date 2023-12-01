// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {FxBaseRootTunnel} from "../../lib/fx-portal/contracts/tunnel/FxBaseRootTunnel.sol";
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

/// @title FxERC20RootTunnel - Smart contract for the L1 token management part
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract FxERC20RootTunnel is FxBaseRootTunnel {
    event FxDepositERC20(address indexed childToken, address indexed rootToken, address from, address indexed to, uint256 amount);
    event FxWithdrawERC20(address indexed rootToken, address indexed childToken, address from, address indexed to, uint256 amount);

    // Child token address
    address public immutable childToken;
    // Root token address
    address public immutable rootToken;

    /// @dev FxERC20RootTunnel constructor.
    /// @param _checkpointManager Checkpoint manager contract.
    /// @param _fxRoot Fx Root contract address.
    /// @param _childToken L2 token address.
    /// @param _rootToken Corresponding L1 token address.
    constructor(address _checkpointManager, address _fxRoot, address _childToken, address _rootToken)
        FxBaseRootTunnel(_checkpointManager, _fxRoot)
    {
        // Check for zero addresses
        if (_checkpointManager == address(0) || _fxRoot == address(0) || _childToken == address(0) ||
            _rootToken == address(0)) {
            revert ZeroAddress();
        }

        childToken = _childToken;
        rootToken = _rootToken;
    }

    /// @dev Withdraws bridged tokens on L1 in order to obtain their original version on L2.
    /// @notice Destination address is the same as the sender address.
    /// @param amount Token amount to be withdrawn.
    function withdraw(uint256 amount) external {
        _withdraw(msg.sender, amount);
    }

    /// @dev Withdraws bridged tokens on L1 in order to obtain their original version on L2 by a specified address.
    /// @param to Destination address on L2.
    /// @param amount Token amount to be withdrawn.
    function withdrawTo(address to, uint256 amount) external {
        // Check for the address to withdraw tokens to
        if (to == address(0)) {
            revert ZeroAddress();
        }

        _withdraw(to, amount);
    }

    /// @dev Receives the token message from L2 and transfers bridged tokens to a specified address.
    /// @param message Incoming bridge message.
    function _processMessageFromChild(bytes memory message) internal override {
        // Decode incoming message from child: (address, address, uint256)
        (address from, address to, uint256 amount) = abi.decode(message, (address, address, uint256));

        // Mints bridged amount of tokens to a specified address
        IERC20(rootToken).mint(to, amount);

        emit FxDepositERC20(childToken, rootToken, from, to, amount);
    }

    /// @dev Withdraws bridged tokens from L1 to get their original tokens on L1 by a specified address.
    /// @notice Reentrancy is not possible as tokens are verified before the contract deployment.
    /// @param to Destination address on L2.
    /// @param amount Token amount to be withdrawn.
    function _withdraw(address to, uint256 amount) internal {
        // Check for the non-zero amount
        if (amount == 0) {
            revert ZeroValue();
        }

        // Encode message for child: (address, address, uint256)
        bytes memory message = abi.encode(msg.sender, to, amount);
        // Send message to child
        _sendMessageToChild(message);

        // Transfer tokens from sender to this contract address
        bool success = IERC20(rootToken).transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert TransferFailed(rootToken, msg.sender, address(this), amount);
        }

        // Burn bridged tokens
        IERC20(rootToken).burn(amount);

        emit FxWithdrawERC20(rootToken, childToken, msg.sender, to, amount);
    }
}
