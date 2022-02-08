// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesCompUpgradeable.sol";

contract veOLA is ERC20VotesCompUpgradeable {
    constructor() initializer {
        __ERC20_init("Governance OLA", "veOLA");
        __ERC20Permit_init("Governance OLA");
    }
}