// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title MockDispenser - Minimal dispenser stand-in for VoteWeighting tests.
/// @dev Records addNominee / removeNominee calls and can be toggled to revert on either,
///      so tests can exercise the VoteWeighting dispenser-call paths with an immutable dispenser.
contract MockDispenser {
    uint256 public addCount;
    uint256 public removeCount;
    bool public revertOnAdd;
    bool public revertOnRemove;

    function setRevertOnAdd(bool value) external {
        revertOnAdd = value;
    }

    function setRevertOnRemove(bool value) external {
        revertOnRemove = value;
    }

    function addNominee(bytes32) external {
        require(!revertOnAdd, "MockDispenser: addNominee reverted");
        addCount++;
    }

    function removeNominee(bytes32) external {
        require(!revertOnRemove, "MockDispenser: removeNominee reverted");
        removeCount++;
    }
}
