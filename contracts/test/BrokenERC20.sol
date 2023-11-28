// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Provided zero address.
error ZeroAddress();


/// @title BrokenERC20 - Smart contract for an ERC20 token with a broken functionality
contract BrokenERC20 is ERC20 {

    constructor() ERC20("Broken ERC20", "BRERC20", 18)
    {}

    /// @dev Mints tokens.
    /// @param account Account address.
    /// @param amount Token amount.
    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    /// @dev Burns tokens.
    /// @param amount Token amount to burn.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @dev Broken transfer function.
    function transfer(address, uint256) public virtual override returns (bool) {
        return false;
    }

    /// @dev Broken transferFrom function.
    function transferFrom(address, address, uint256) public virtual override returns (bool) {
        return false;
    }
}