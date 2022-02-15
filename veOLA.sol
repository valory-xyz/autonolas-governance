// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesCompUpgradeable.sol";

/// @title veOLA - Smart contract for the veOLA governance token
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
// solhint-disable-next-line
contract veOLA is ERC20VotesCompUpgradeable {
    constructor() initializer {
        // ERC20 initialization
        __ERC20_init("Governance OLA", "veOLA");
        // ERC20 Permit extension allowing approvals to be made via signatures
        __ERC20Permit_init("Governance OLA");
        // Mint tokens
        // TODO: Adjust before production launch
        _mint(msg.sender, 1000000 * (10 ** decimals()));
    }
}