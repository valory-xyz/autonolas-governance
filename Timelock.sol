// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

/// @title Timelock - Smart contract for the timelock
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Timelock is TimelockControllerUpgradeable {
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors) initializer {
        // Initialize the timelock with minimum delay in number of blocks, list of proposer and executor addresses
        __TimelockController_init(minDelay, proposers, executors);
    }
}