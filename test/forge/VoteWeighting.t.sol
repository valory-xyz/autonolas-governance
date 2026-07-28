// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {OLAS} from "../../contracts/OLAS.sol";
import {veOLAS} from "../../contracts/veOLAS.sol";
import {VoteWeighting, OwnerOnly, NomineeDoesNotExist, NomineeNotRemoved, ZeroValue} from "../../contracts/VoteWeighting.sol";

/// @title VoteWeightingTest - Unit tests for the VoteWeighting security-redeploy fixes
/// @dev Deploys the real OLAS + veOLAS + VoteWeighting stack locally (deterministic, no fork).
///      Covers findings #8 (removeNominee accounting DoS), #11 (OwnerOnly arg order), #18
///      (relative-weight clamp), #19 (last-element swap guard) and #20 (revoke checkpoint drift).
///      Run: forge test --match-contract VoteWeightingTest -vvv
contract VoteWeightingTest is Test {
    uint256 internal constant WEEK = 604_800;
    uint256 internal constant MAXTIME = 4 * 365 * 86400;
    uint256 internal constant MAX_WEIGHT = 10_000;
    uint256 internal constant CHAIN_ID = 1;

    OLAS internal olas;
    veOLAS internal ve;
    VoteWeighting internal vw;

    address internal owner = address(this);
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    // Sample nominee target addresses
    address internal n1 = makeAddr("nominee1");
    address internal n2 = makeAddr("nominee2");
    address internal n3 = makeAddr("nominee3");

    function setUp() public {
        // Warp to a realistic timestamp so week-rounding of veOLAS locks is well-defined
        vm.warp(1_700_000_000);

        olas = new OLAS();
        ve = new veOLAS(address(olas), "Voting Escrow OLAS", "veOLAS");
        vw = new VoteWeighting(address(ve));

        // This test contract is the OLAS minter; fund the voters
        olas.mint(alice, 1_000_000 ether);
        olas.mint(bob, 1_000_000 ether);
        olas.mint(carol, 1_000_000 ether);
    }

    // ----------------------------------------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------------------------------------

    function _b32(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }

    function _hash(address a, uint256 chainId) internal pure returns (bytes32) {
        return keccak256(abi.encode(_b32(a), chainId));
    }

    function _lock(address user, uint256 amount, uint256 duration) internal {
        // veOLAS createLock takes a lock DURATION (it adds block.timestamp internally)
        vm.startPrank(user);
        olas.approve(address(ve), amount);
        ve.createLock(amount, duration);
        vm.stopPrank();
    }

    function _vote(address user, address nominee, uint256 chainId, uint256 weight) internal {
        vm.prank(user);
        vw.voteForNomineeWeights(_b32(nominee), chainId, weight);
    }

    function _nomineeBias(address nominee, uint256 chainId) internal view returns (uint256 bias) {
        (bias, ) = vw.pointsWeight(_hash(nominee, chainId), vw.timeWeight(_hash(nominee, chainId)));
    }

    function _sumSlopeAtNextTime() internal view returns (uint256 slope) {
        (, slope) = vw.pointsSum(vw.timeSum());
    }

    // ----------------------------------------------------------------------------------------------
    // Finding #8 - removeNominee accounting DoS (primary)
    // ----------------------------------------------------------------------------------------------

    /// @dev The exact class of sequence that permanently bricks the pre-fix contract:
    ///      voters allocate to a nominee, the nominee is removed WITHOUT any unvote, the voter locks
    ///      then expire, and a second still-active nominee retains weight. On the old build the
    ///      retained slope + changesSum over-decays the sum to zero while the second nominee weight
    ///      stays positive, so a later removeNominee underflows (0 - weight) and every checkpoint
    ///      walk reverts thereafter. Post-fix: the walk never reverts and the aggregate stays exact.
    function test_RemoveWithoutUnvote_NoCheckpointDoS() public {
        // Two short locks feeding nominee 1, one long lock feeding nominee 2
        _lock(alice, 1_000 ether, 20 * WEEK);
        _lock(bob, 1_000 ether, 20 * WEEK);
        _lock(carol, 1_000 ether, 200 * WEEK);

        vw.addNomineeEVM(n1, CHAIN_ID);
        vw.addNomineeEVM(n2, CHAIN_ID);

        _vote(alice, n1, CHAIN_ID, MAX_WEIGHT);
        _vote(bob, n1, CHAIN_ID, MAX_WEIGHT);
        _vote(carol, n2, CHAIN_ID, MAX_WEIGHT);

        // Owner removes nominee 1; nobody unvotes / revokes
        vw.removeNominee(_b32(n1), CHAIN_ID);

        // Walk the checkpoint week by week well past the expiry of the nominee-1 locks
        for (uint256 i = 0; i < 40; ++i) {
            vm.warp(block.timestamp + WEEK);
            // Must never revert (pre-fix this underflows once the phantom slope drains the sum)
            vw.checkpoint();
        }

        // Nominee 2 still has weight; a subsequent removal must not underflow
        vw.checkpointNominee(_b32(n2), CHAIN_ID);
        uint256 n2Weight = vw.getNomineeWeight(_b32(n2), CHAIN_ID);
        assertGt(n2Weight, 0, "nominee 2 should still carry weight");

        // Aggregate equals the only surviving nominee (nominee 1 fully reconciled out)
        assertEq(vw.getWeightsSum(), n2Weight, "sum must equal the single surviving nominee weight");

        // The historically-reverting call: removing the second nominee while sum > 0
        vw.removeNominee(_b32(n2), CHAIN_ID);
        assertEq(vw.getWeightsSum(), 0, "sum must be zero after removing the last nominee");
    }

    /// @dev removeNominee must subtract the removed nominee's active slope from the aggregate sum
    ///      slope AND strip its future changesSum entries, so no phantom decrement survives.
    function test_RemoveNominee_ReconcilesSlopeAndChangesSum() public {
        _lock(alice, 1_000 ether, 30 * WEEK);
        _lock(bob, 1_000 ether, 100 * WEEK);

        vw.addNomineeEVM(n1, CHAIN_ID);
        vw.addNomineeEVM(n2, CHAIN_ID);

        _vote(alice, n1, CHAIN_ID, MAX_WEIGHT);
        _vote(bob, n2, CHAIN_ID, MAX_WEIGHT);

        // Sum slope currently includes both alice (n1) and bob (n2)
        uint256 sumSlopeBefore = _sumSlopeAtNextTime();
        (uint256 aliceSlope, , uint256 aliceEnd) = vw.voteUserSlopes(alice, _hash(n1, CHAIN_ID));
        assertGt(aliceSlope, 0, "alice slope should be set");

        // changesSum at alice's lock end includes alice's scheduled decrement
        uint256 changesSumAtAliceEndBefore = vw.changesSum(aliceEnd);
        assertGe(changesSumAtAliceEndBefore, aliceSlope, "changesSum must contain alice slope pre-removal");

        vw.removeNominee(_b32(n1), CHAIN_ID);

        // Aggregate slope dropped by exactly alice's slope
        assertEq(_sumSlopeAtNextTime(), sumSlopeBefore - aliceSlope, "sum slope must drop by removed nominee slope");
        // The phantom changesSum decrement for the removed nominee is gone
        assertEq(vw.changesSum(aliceEnd), changesSumAtAliceEndBefore - aliceSlope, "changesSum decrement must be stripped");
        assertEq(vw.changesWeight(_hash(n1, CHAIN_ID), aliceEnd), 0, "nominee changesWeight must be cleared");
    }

    /// @dev revoke after removal must only release the caller's own power and must NOT mutate the
    ///      aggregate again (that was reconciled in removeNominee) - i.e. no double subtraction.
    function test_RevokeRemovedNominee_NoDoubleCount() public {
        _lock(alice, 1_000 ether, 50 * WEEK);

        vw.addNomineeEVM(n1, CHAIN_ID);
        _vote(alice, n1, CHAIN_ID, MAX_WEIGHT);

        vw.removeNominee(_b32(n1), CHAIN_ID);

        // Snapshot aggregate state after removal
        (uint256 sumBiasBefore, uint256 sumSlopeBefore) = vw.pointsSum(vw.timeSum());
        (, , uint256 aliceEnd) = vw.voteUserSlopes(alice, _hash(n1, CHAIN_ID));
        uint256 changesSumBefore = vw.changesSum(aliceEnd);
        assertEq(vw.voteUserPower(alice), MAX_WEIGHT, "alice power fully used pre-revoke");

        // Alice revokes
        vm.prank(alice);
        vw.revokeRemovedNomineeVotingPower(_b32(n1), CHAIN_ID);

        // Power released, per-user slope cleared
        assertEq(vw.voteUserPower(alice), 0, "alice power must be released");
        (uint256 slopeAfter, uint256 powerAfter, uint256 endAfter) = vw.voteUserSlopes(alice, _hash(n1, CHAIN_ID));
        assertEq(slopeAfter, 0, "user slope cleared");
        assertEq(powerAfter, 0, "user power cleared");
        assertEq(endAfter, 0, "user end cleared");

        // Aggregate untouched by revoke (would be double-subtracted on the old build)
        (uint256 sumBiasAfter, uint256 sumSlopeAfter) = vw.pointsSum(vw.timeSum());
        assertEq(sumBiasAfter, sumBiasBefore, "sum bias must be unchanged by revoke");
        assertEq(sumSlopeAfter, sumSlopeBefore, "sum slope must be unchanged by revoke");
        assertEq(vw.changesSum(aliceEnd), changesSumBefore, "changesSum must be unchanged by revoke");
    }

    /// @dev Finding #20: revoke run several weeks after removal must not corrupt accounting. Since the
    ///      fixed revoke no longer writes any checkpoint slot, a stale next-week slot cannot be missed.
    function test_RevokeRemovedNominee_LateNoDrift() public {
        _lock(alice, 1_000 ether, 100 * WEEK);
        vw.addNomineeEVM(n1, CHAIN_ID);
        _vote(alice, n1, CHAIN_ID, MAX_WEIGHT);

        vw.removeNominee(_b32(n1), CHAIN_ID);

        // Advance several weeks so the "next week" slot is well past the removal checkpoint
        vm.warp(block.timestamp + 5 * WEEK);
        vw.checkpoint();

        (uint256 sumBiasBefore, uint256 sumSlopeBefore) = vw.pointsSum(vw.timeSum());

        vm.prank(alice);
        vw.revokeRemovedNomineeVotingPower(_b32(n1), CHAIN_ID);

        (uint256 sumBiasAfter, uint256 sumSlopeAfter) = vw.pointsSum(vw.timeSum());
        assertEq(sumBiasAfter, sumBiasBefore, "late revoke must not change sum bias");
        assertEq(sumSlopeAfter, sumSlopeBefore, "late revoke must not change sum slope");
        assertEq(vw.voteUserPower(alice), 0, "power released on late revoke");
    }

    // ----------------------------------------------------------------------------------------------
    // Finding #11 - OwnerOnly revert-data argument order
    // ----------------------------------------------------------------------------------------------

    function test_RemoveNominee_OwnerOnlyArgOrder() public {
        vw.addNomineeEVM(n1, CHAIN_ID);

        // Non-owner caller: revert must report (sender, owner) in the declared order
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnerOnly.selector, alice, owner));
        vw.removeNominee(_b32(n1), CHAIN_ID);
    }

    // ----------------------------------------------------------------------------------------------
    // Finding #19 - last-element swap guard
    // ----------------------------------------------------------------------------------------------

    function test_RemoveNominee_RemoveLastElement_NoDanglingId() public {
        vw.addNomineeEVM(n1, CHAIN_ID); // id 1
        vw.addNomineeEVM(n2, CHAIN_ID); // id 2 (last)

        vw.removeNominee(_b32(n2), CHAIN_ID); // remove the last element

        // The just-removed nominee must NOT retain a dangling nominee id
        assertEq(vw.getNomineeId(_b32(n2), CHAIN_ID), 0, "removed last nominee id must be zeroed");
        assertGt(vw.getRemovedNomineeId(_b32(n2), CHAIN_ID), 0, "removed nominee must be recorded");
        // The other nominee is untouched
        assertEq(vw.getNomineeId(_b32(n1), CHAIN_ID), 1, "surviving nominee id intact");
        assertEq(vw.getNumNominees(), 1, "one nominee remains");
    }

    function test_RemoveNominee_RemoveFirstElement_ShufflesLast() public {
        vw.addNomineeEVM(n1, CHAIN_ID); // id 1
        vw.addNomineeEVM(n2, CHAIN_ID); // id 2

        vw.removeNominee(_b32(n1), CHAIN_ID); // remove the first; last (n2) shuffles into id 1

        assertEq(vw.getNomineeId(_b32(n1), CHAIN_ID), 0, "removed nominee id zeroed");
        assertEq(vw.getNomineeId(_b32(n2), CHAIN_ID), 1, "last nominee shuffled into freed id");
        assertEq(vw.getNumNominees(), 1, "one nominee remains");
    }

    // ----------------------------------------------------------------------------------------------
    // Finding #18 - relative weight capped at 1e18
    // ----------------------------------------------------------------------------------------------

    function test_NomineeRelativeWeight_FullAllocationIsOne() public {
        _lock(alice, 1_000 ether, 100 * WEEK);
        vw.addNomineeEVM(n1, CHAIN_ID);
        _vote(alice, n1, CHAIN_ID, MAX_WEIGHT);

        // Advance a week so the coming checkpoint slot is populated
        vm.warp(block.timestamp + WEEK);
        vw.nomineeRelativeWeightWrite(_b32(n1), CHAIN_ID, block.timestamp);

        (uint256 rw, ) = vw.nomineeRelativeWeight(_b32(n1), CHAIN_ID, block.timestamp);
        assertEq(rw, 1e18, "single fully-allocated nominee must be exactly 1e18");
    }

    function test_NomineeRelativeWeight_NeverExceedsOne() public {
        _lock(alice, 1_000 ether, 100 * WEEK);
        _lock(bob, 500 ether, 60 * WEEK);
        vw.addNomineeEVM(n1, CHAIN_ID);
        vw.addNomineeEVM(n2, CHAIN_ID);
        _vote(alice, n1, CHAIN_ID, MAX_WEIGHT);
        _vote(bob, n2, CHAIN_ID, MAX_WEIGHT);

        vm.warp(block.timestamp + WEEK);
        vw.nomineeRelativeWeightWrite(_b32(n1), CHAIN_ID, block.timestamp);
        vw.nomineeRelativeWeightWrite(_b32(n2), CHAIN_ID, block.timestamp);

        (uint256 rw1, ) = vw.nomineeRelativeWeight(_b32(n1), CHAIN_ID, block.timestamp);
        (uint256 rw2, ) = vw.nomineeRelativeWeight(_b32(n2), CHAIN_ID, block.timestamp);
        assertLe(rw1, 1e18, "relative weight must not exceed 1e18");
        assertLe(rw2, 1e18, "relative weight must not exceed 1e18");
    }

    // ----------------------------------------------------------------------------------------------
    // Finding #8 - additional reconciliation edge cases
    // ----------------------------------------------------------------------------------------------

    /// @dev Strong global invariant: after any sequence of votes / removals / time advances, the
    ///      aggregate sum bias must equal the sum of the surviving nominees' individual biases.
    function _assertSumConsistent(address[] memory active) internal {
        uint256 total;
        for (uint256 i = 0; i < active.length; ++i) {
            vw.checkpointNominee(_b32(active[i]), CHAIN_ID);
            total += vw.getNomineeWeight(_b32(active[i]), CHAIN_ID);
        }
        vw.checkpoint();
        assertEq(vw.getWeightsSum(), total, "aggregate must equal sum of surviving nominee weights");
    }

    /// @dev Multiple voters on the same nominee, each with a different lock end: removal must strip
    ///      every voter's slope and changesSum entry, and the surviving nominee must stay consistent.
    function test_RemoveNominee_MultiVoter_FullReconcile() public {
        _lock(alice, 1_000 ether, 30 * WEEK);
        _lock(bob, 2_000 ether, 80 * WEEK);
        _lock(carol, 1_500 ether, 200 * WEEK);

        vw.addNomineeEVM(n1, CHAIN_ID);
        vw.addNomineeEVM(n2, CHAIN_ID);

        _vote(alice, n1, CHAIN_ID, MAX_WEIGHT);
        _vote(bob, n1, CHAIN_ID, MAX_WEIGHT);
        _vote(carol, n2, CHAIN_ID, MAX_WEIGHT);

        (uint256 aliceSlope, , uint256 aliceEnd) = vw.voteUserSlopes(alice, _hash(n1, CHAIN_ID));
        (uint256 bobSlope, , uint256 bobEnd) = vw.voteUserSlopes(bob, _hash(n1, CHAIN_ID));
        uint256 sumSlopeBefore = _sumSlopeAtNextTime();

        vw.removeNominee(_b32(n1), CHAIN_ID);

        // Sum slope dropped by both nominee-1 voters' slopes
        assertEq(_sumSlopeAtNextTime(), sumSlopeBefore - aliceSlope - bobSlope, "both voter slopes removed");
        // Both scheduled decrements stripped from the aggregate
        assertEq(vw.changesWeight(_hash(n1, CHAIN_ID), aliceEnd), 0, "alice changesWeight cleared");
        assertEq(vw.changesWeight(_hash(n1, CHAIN_ID), bobEnd), 0, "bob changesWeight cleared");

        // Only nominee 2 survives; invariant holds now and across a long horizon
        address[] memory active = new address[](1);
        active[0] = n2;
        _assertSumConsistent(active);
        for (uint256 i = 0; i < 60; ++i) {
            vm.warp(block.timestamp + WEEK);
            vw.checkpoint();
        }
        _assertSumConsistent(active);
    }

    /// @dev A voter whose lock already expired (its changesSum decrement was already applied by a
    ///      prior checkpoint) must not cause an underflow or double subtraction on removal.
    function test_RemoveNominee_ExpiredVoter_NoUnderflow() public {
        _lock(alice, 1_000 ether, 3 * WEEK); // short: will expire before removal
        _lock(carol, 1_000 ether, 200 * WEEK);

        vw.addNomineeEVM(n1, CHAIN_ID);
        vw.addNomineeEVM(n2, CHAIN_ID);

        _vote(alice, n1, CHAIN_ID, MAX_WEIGHT);
        _vote(carol, n2, CHAIN_ID, MAX_WEIGHT);

        // Advance past alice's lock end so her changesSum decrement is processed by the walk
        for (uint256 i = 0; i < 5; ++i) {
            vm.warp(block.timestamp + WEEK);
            vw.checkpoint();
        }
        vw.checkpointNominee(_b32(n1), CHAIN_ID);
        assertEq(vw.getNomineeWeight(_b32(n1), CHAIN_ID), 0, "nominee 1 weight decayed to zero");

        // Removal of the now-empty nominee must succeed and keep the survivor consistent
        vw.removeNominee(_b32(n1), CHAIN_ID);
        address[] memory active = new address[](1);
        active[0] = n2;
        _assertSumConsistent(active);
    }

    /// @dev Changing a vote before removal, then removing, must reconcile the updated slope.
    function test_ChangeVoteThenRemove_Consistent() public {
        _lock(alice, 1_000 ether, 100 * WEEK);
        _lock(carol, 1_000 ether, 150 * WEEK);

        vw.addNomineeEVM(n1, CHAIN_ID);
        vw.addNomineeEVM(n2, CHAIN_ID);

        _vote(alice, n1, CHAIN_ID, 5_000);
        _vote(carol, n2, CHAIN_ID, MAX_WEIGHT);

        // WEIGHT_VOTE_DELAY is 10 days; advance before re-voting the same nominee
        vm.warp(block.timestamp + 11 days);
        _vote(alice, n1, CHAIN_ID, 8_000); // change allocation

        vw.removeNominee(_b32(n1), CHAIN_ID);

        address[] memory active = new address[](1);
        active[0] = n2;
        _assertSumConsistent(active);
    }

    /// @dev Zeroing the weight (proper unvote) before removal leaves an already-clean aggregate.
    function test_ZeroWeightThenRemove_Consistent() public {
        _lock(alice, 1_000 ether, 100 * WEEK);
        _lock(carol, 1_000 ether, 150 * WEEK);

        vw.addNomineeEVM(n1, CHAIN_ID);
        vw.addNomineeEVM(n2, CHAIN_ID);

        _vote(alice, n1, CHAIN_ID, MAX_WEIGHT);
        _vote(carol, n2, CHAIN_ID, MAX_WEIGHT);

        vm.warp(block.timestamp + 11 days);
        _vote(alice, n1, CHAIN_ID, 0); // proper unvote

        assertEq(vw.voteUserPower(alice), 0, "power freed by zero-weight vote");

        vw.removeNominee(_b32(n1), CHAIN_ID);
        address[] memory active = new address[](1);
        active[0] = n2;
        _assertSumConsistent(active);
    }

    /// @dev Batch voting followed by removal stays consistent.
    function test_BatchVoteThenRemove_Consistent() public {
        _lock(alice, 3_000 ether, 120 * WEEK);

        vw.addNomineeEVM(n1, CHAIN_ID);
        vw.addNomineeEVM(n2, CHAIN_ID);
        vw.addNomineeEVM(n3, CHAIN_ID);

        bytes32[] memory accounts = new bytes32[](3);
        accounts[0] = _b32(n1);
        accounts[1] = _b32(n2);
        accounts[2] = _b32(n3);
        uint256[] memory chainIds = new uint256[](3);
        chainIds[0] = CHAIN_ID;
        chainIds[1] = CHAIN_ID;
        chainIds[2] = CHAIN_ID;
        uint256[] memory weights = new uint256[](3);
        weights[0] = 5_000;
        weights[1] = 3_000;
        weights[2] = 2_000;

        vm.prank(alice);
        vw.voteForNomineeWeightsBatch(accounts, chainIds, weights);

        vw.removeNominee(_b32(n2), CHAIN_ID);

        address[] memory active = new address[](2);
        active[0] = n1;
        active[1] = n3;
        _assertSumConsistent(active);
    }

    // ----------------------------------------------------------------------------------------------
    // Standard revert paths (regression guards around the modified functions)
    // ----------------------------------------------------------------------------------------------

    function test_Revoke_NonRemovedNominee_Reverts() public {
        _lock(alice, 1_000 ether, 100 * WEEK);
        vw.addNomineeEVM(n1, CHAIN_ID);
        _vote(alice, n1, CHAIN_ID, MAX_WEIGHT);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NomineeNotRemoved.selector, _b32(n1), CHAIN_ID));
        vw.revokeRemovedNomineeVotingPower(_b32(n1), CHAIN_ID);
    }

    function test_Revoke_Twice_Reverts() public {
        _lock(alice, 1_000 ether, 100 * WEEK);
        vw.addNomineeEVM(n1, CHAIN_ID);
        _vote(alice, n1, CHAIN_ID, MAX_WEIGHT);
        vw.removeNominee(_b32(n1), CHAIN_ID);

        vm.prank(alice);
        vw.revokeRemovedNomineeVotingPower(_b32(n1), CHAIN_ID);

        // Second revoke has nothing to release
        vm.prank(alice);
        vm.expectRevert(ZeroValue.selector);
        vw.revokeRemovedNomineeVotingPower(_b32(n1), CHAIN_ID);
    }

    function test_RemoveNominee_NonExistent_Reverts() public {
        vm.expectRevert(abi.encodeWithSelector(NomineeDoesNotExist.selector, _b32(n1), CHAIN_ID));
        vw.removeNominee(_b32(n1), CHAIN_ID);
    }
}
