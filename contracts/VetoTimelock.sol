// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Timelock} from "./Timelock.sol";

/// @dev This function is permanently disabled on the veto stack.
error Unsupported();

/// @title VetoTimelock - Timelock with a permanently fixed delay, for the cancel-only veto stack.
/// @author Valory AG
/// @notice A `Timelock` (OZ v4.8.3 `TimelockController`) whose `updateDelay` is disabled, so the delay
///         chosen at construction can never change. Deployed with a zero delay so the veto path executes
///         without waiting, and that delay is fixed for the life of the contract.
contract VetoTimelock is Timelock {
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors)
        Timelock(minDelay, proposers, executors)
    {}

    /// @dev Permanently disabled: the delay is fixed at construction.
    function updateDelay(uint256) external pure override {
        revert Unsupported();
    }
}
