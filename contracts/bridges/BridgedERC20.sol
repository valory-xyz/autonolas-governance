// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Provided zero address.
error ZeroAddress();


/// @title BridgedERC20 - Smart contract for bridged ERC20 token
/// @dev Bridged token contract is owned by the bridge mediator contract, and thus the token representation from
///      another chain must be minted and burned solely by the bridge mediator contract.
contract BridgedERC20 is ERC20 {
    event OwnerUpdated(address indexed owner);

    // Bridged token owner
    address public owner;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol, _decimals) {
        owner = msg.sender;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
        // Only the contract owner is allowed to change the owner
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Zero address check
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Mints bridged tokens.
    /// @param account Account address.
    /// @param amount Bridged token amount.
    function mint(address account, uint256 amount) external {
        // Only the contract owner is allowed to mint
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }
        
        _mint(account, amount);
    }

    /// @dev Burns bridged tokens.
    /// @param amount Bridged token amount to burn.
    function burn(uint256 amount) external {
        // Only the contract owner is allowed to burn
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        _burn(msg.sender, amount);
    }
}