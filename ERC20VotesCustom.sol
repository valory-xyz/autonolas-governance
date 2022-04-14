// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC20/extensions/ERC20Votes.sol)

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IErrors.sol";

/// @title ERC20 Votes Custom Upgradeable - Smart contract that customizes OpenZeppelin's ERC20VotesUpgradeable
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
abstract contract ERC20VotesCustom is IErrors, IVotes, IERC20 {

    /// @dev Bans the transfer of this token.
    function transfer(address to, uint256 amount) external virtual override returns (bool) {
        revert NonTransferrable(address(this));
    }

    /// @dev Bans the approval of this token.
    function approve(address spender, uint256 amount) external virtual override returns (bool) {
        revert NonTransferrable(address(this));
    }

    /// @dev Bans the transferFrom of this token.
    function transferFrom(address from, address to, uint256 amount) external virtual override returns (bool) {
        revert NonTransferrable(address(this));
    }

    /// @dev Compatibility with IERC20.
    function allowance(address owner, address spender) external view virtual override returns (uint256)
    {}

    /// @dev Compatibility with IVotes.
    function delegates(address account) external view virtual override returns (address)
    {}

    /// @dev Compatibility with IVotes.
    function delegate(address delegatee) external virtual override
    {}

    /// @dev Compatibility with IVotes.
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        external virtual override
    {}
}
