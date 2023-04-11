// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "../../../lib/solmate/src/tokens/ERC20.sol";

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required owner address.
error OwnerOnly(address sender, address owner);

/// @dev Provided zero address.
error ZeroAddress();

/// @title ChildMockERC20 - Mock of ERC20 smart contract on the L2 side
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author AL
contract ChildMockERC20 is ERC20 {
    event OwnerUpdated(address indexed owner);

    // Owner address
    address public owner;

    constructor() ERC20("ChildMockERC20", "CMERC20", 18) {
        owner = msg.sender;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Mints tokens.
    /// @param account Account address.
    /// @param amount Token amount.
    function mint(address account, uint256 amount) external {
        // Access control
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        _mint(account, amount);
    }
}