// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title Timelock - Smart contract for the timelock
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @dev The OpenZeppelin functions are used as is, using the last OZ version (4.6) on the date of deployment.
contract Timelock is TimelockController {
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors)
        TimelockController(minDelay, proposers, executors)
    {}
}