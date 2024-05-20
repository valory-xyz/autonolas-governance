// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @title MockTimelock - Mock of Timelock contract for community multisig management
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author AL
contract MockTreasury {
    event PauseTreasury();
    event UnpauseTreasury();

    // Owner address
    address public owner;
    // Contract pausing
    uint8 public paused = 1;

    constructor(address _timelock) {
        owner = _timelock;
    }

    /// @dev Pauses the contract.
    function pause() external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = 2;
        emit PauseTreasury();
    }

    /// @dev Unpauses the contract.
    function unpause() external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = 1;
        emit UnpauseTreasury();
    }
}