// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {VetoGovernor} from "../../contracts/VetoGovernor.sol";
import {VetoTimelock} from "../../contracts/VetoTimelock.sol";

/// @dev Minimal voting token.
contract MockVotesToken is ERC20, ERC20Permit, ERC20Votes {
    constructor() ERC20("Votes", "VOTES") ERC20Permit("Votes") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }
}

/// @dev Target of the proposals.
contract Counter {
    uint256 public count;

    function increment() external {
        ++count;
    }
}

/// @dev VetoGovernor executes only proposals it queued itself.
///      The timelock operation id depends on the batch and its description hash, not on the proposal, so an identical
///      batch scheduled on the veto timelock by another proposer would otherwise be executable through a Succeeded
///      proposal that was never queued.
///      Run: forge test --match-contract VetoGovernorExecuteTest -vvv
contract VetoGovernorExecuteTest is Test {
    uint256 internal constant VOTING_DELAY = 1;
    uint256 internal constant VOTING_PERIOD = 10;
    uint256 internal constant GOVERNOR_DELAY = 1 days;
    address internal constant MAIN_TIMELOCK = address(0x7A11);
    address internal constant VOTER = address(0xB0B);
    address internal constant OTHER_PROPOSER = address(0x07E5);

    MockVotesToken internal token;
    VetoTimelock internal timelock;
    VetoGovernor internal governor;
    Counter internal counter;

    address[] internal targets;
    uint256[] internal values;
    bytes[] internal calldatas;
    string internal constant DESCRIPTION = "Increment the counter";

    function setUp() public {
        token = new MockVotesToken();
        token.mint(VOTER, 1_000 ether);
        vm.prank(VOTER);
        token.delegate(VOTER);
        vm.roll(block.number + 1);

        timelock = new VetoTimelock(0, new address[](0), new address[](0));
        governor = new VetoGovernor(IVotes(address(token)), TimelockController(payable(address(timelock))),
            VOTING_DELAY, VOTING_PERIOD, 0, 4, GOVERNOR_DELAY, MAIN_TIMELOCK);
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        // A second proposer on the veto timelock, able to schedule batches directly
        timelock.grantRole(timelock.PROPOSER_ROLE(), OTHER_PROPOSER);

        counter = new Counter();
        targets.push(address(counter));
        values.push(0);
        calldatas.push(abi.encodeCall(Counter.increment, ()));
    }

    /// @dev Proposes, votes and closes the vote: the proposal is Succeeded and not queued.
    function _proposeAndPass() internal returns (uint256 proposalId) {
        vm.prank(VOTER);
        proposalId = governor.propose(targets, values, calldatas, DESCRIPTION);
        vm.roll(block.number + VOTING_DELAY + 1);
        vm.prank(VOTER);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded), "Succeeded");
        assertEq(governor.proposalEta(proposalId), 0, "not queued");
    }

    /// @dev Another proposer makes the identical batch ready on the timelock; the never-queued Succeeded proposal
    ///      must not execute it.
    function test_execute_neverQueued_identicalBatchReadyOnTimelock_reverts() public {
        uint256 proposalId = _proposeAndPass();
        bytes32 descriptionHash = keccak256(bytes(DESCRIPTION));

        // The same operation the Governor's queue() would schedule, scheduled directly by another proposer
        vm.prank(OTHER_PROPOSER);
        timelock.scheduleBatch(targets, values, calldatas, 0, descriptionHash, GOVERNOR_DELAY);
        vm.warp(block.timestamp + GOVERNOR_DELAY + 1);
        assertTrue(timelock.isOperationReady(timelock.hashOperationBatch(targets, values, calldatas, 0, descriptionHash)),
            "operation ready on the timelock");

        vm.expectRevert(abi.encodeWithSignature("NotQueued(uint256)", proposalId));
        governor.execute(targets, values, calldatas, descriptionHash);
        assertEq(counter.count(), 0, "nothing executed");
    }

    /// @dev A Succeeded proposal that was never queued cannot execute at all.
    function test_execute_neverQueued_reverts() public {
        uint256 proposalId = _proposeAndPass();

        vm.expectRevert(abi.encodeWithSignature("NotQueued(uint256)", proposalId));
        governor.execute(targets, values, calldatas, keccak256(bytes(DESCRIPTION)));
    }

    /// @dev The normal path is unchanged: propose, vote, queue, wait, execute.
    function test_execute_queuedProposal_executes() public {
        uint256 proposalId = _proposeAndPass();
        bytes32 descriptionHash = keccak256(bytes(DESCRIPTION));

        governor.queue(targets, values, calldatas, descriptionHash);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued), "Queued");
        assertGt(governor.proposalEta(proposalId), 0, "queue record");

        vm.warp(block.timestamp + GOVERNOR_DELAY + 1);
        governor.execute(targets, values, calldatas, descriptionHash);

        assertEq(counter.count(), 1, "executed");
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed), "Executed");
    }
}
