// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC20/extensions/ERC20Votes.sol)

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "../interfaces/IErrors.sol";

/// @title ERC20 Votes Custom Upgradeable - Smart contract that customizes OpenZeppelin's ERC20VotesUpgradeable
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
abstract contract ERC20VotesCustom is IErrors, ERC20Votes {
    constructor(string memory _name, string memory _symbol) ERC20Permit(_name) ERC20(_name, _symbol)
    {}

    /// @dev Gets the voting power at a specific block number.
    /// @param account Account address.
    /// @param blockNumber Block number.
    /// @return Voting power
    function balanceOfAt(address account, uint256 blockNumber) public view virtual returns (uint256) {
    }

    /// @dev Calculate total voting power at some point in the past.
    /// @param blockNumber Block number to calculate the total voting power at.
    /// @return supply Total voting power.
    function totalSupplyAt(uint256 blockNumber) public view virtual returns (uint256) {
    }

    /// @dev Gets the voting power.
    /// @param account Account address.
    function getVotes(address account) public view override returns (uint256 balance) {
        balance = balanceOf(account);
    }

    /// @dev Gets voting power at a specific block number.
    /// @param account Account address.
    /// @param blockNumber Block number.
    /// @return balance Voting balance / power.
    function getPastVotes(address account, uint256 blockNumber) public view override returns (uint256 balance) {
        balance = balanceOfAt(account, blockNumber);
    }

    /// @dev Calculate total voting power at some point in the past.
    /// @param blockNumber Block number to calculate the total voting power at.
    /// @return supply Total voting power.
    function getPastTotalSupply(uint256 blockNumber) public view override returns (uint256 supply) {
        supply = totalSupplyAt(blockNumber);
    }

    /// @dev Bans transfers of this token.
    function _transfer(address sender, address recipient, uint256 amount) internal override {
        revert NonTransferrable(address(this));
    }

    /// @dev Bans approval of this token.
    function _approve(address owner, address spender, uint256 amount) internal override {
        revert NonTransferrable(address(this));
    }
}
