// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title Timelock - Smart contract for the timelock
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Timelock is TimelockController {
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors)
        TimelockController(minDelay, proposers, executors)
    {}
}