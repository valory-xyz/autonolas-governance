// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {OLAS} from "../../contracts/OLAS.sol";
import {veOLAS} from "../../contracts/veOLAS.sol";
import {VoteWeighting, OwnerOnly, NomineeDoesNotExist, NomineeNotRemoved, ZeroValue} from "../../contracts/VoteWeighting.sol";
import {MockDispenser} from "../../contracts/test/MockDispenser.sol";

/// @title VoteWeightingTest - Unit tests for the VoteWeighting security-redeploy fixes
/// @dev Deploys the real OLAS + veOLAS + VoteWeighting stack locally (deterministic, no fork).
///      Covers findings #8 (removeNominee accounting DoS), #11 (OwnerOnly arg order), #18
///      (relative-weight clamp), #19 (last-element swap guard), #20 (revoke checkpoint drift), #26 (catch-up
///      cursor fast-forward past the 250-week horizon) and #27 / tokenomics #42 (nominee registration checks).
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
        vw = new VoteWeighting(address(ve), address(0));

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
    /// @notice NOT a regression test: this case passes on the pre-fix contract too. It is a
    ///         consistency check on the post-fix reconciliation, kept for coverage of the
    ///         already-expired-voter path. The regression tests that fail on the pre-fix build are
    ///         test_RemoveWithoutUnvote_NoCheckpointDoS, test_RemoveNominee_ReconcilesSlopeAndChangesSum
    ///         and test_RemoveNominee_MultiVoter_FullReconcile. Renamed from
    ///         test_RemoveNominee_ExpiredVoter_NoUnderflow, whose name implied regression coverage
    ///         it does not provide.
    function test_RemoveNominee_ExpiredVoter_Consistent() public {
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

    // ----------------------------------------------------------------------------------------------
    // #26 - catch-up cursors fast-forward past the 250-week horizon
    // ----------------------------------------------------------------------------------------------

    uint256 internal constant HORIZON = 250 * WEEK;

    function _nextBoundary() internal view returns (uint256) {
        return (block.timestamp / WEEK + 1) * WEEK;
    }

    function _sumPoint(uint256 time) internal view returns (uint256 bias, uint256 slope) {
        (bias, slope) = vw.pointsSum(time);
    }

    function _weightPoint(address nominee, uint256 time) internal view returns (uint256 bias, uint256 slope) {
        (bias, slope) = vw.pointsWeight(_hash(nominee, CHAIN_ID), time);
    }

    /// @dev Expected (bias, slope) one vote contributes at nextTime, as voteForNomineeWeights computes it.
    function _contribution(address user, uint256 weight, uint256 nextTime)
        internal
        view
        returns (uint256 bias, uint256 slope)
    {
        slope = uint256(uint128(ve.getLastUserPoint(user).slope)) * weight / MAX_WEIGHT;
        bias = slope * (ve.lockedEnd(user) - nextTime);
    }

    /// @dev The walk reaches the cursor + 250 weeks at most, so a timestamp one second short of that still advances
    ///      the cursor normally. Passes before and after the fix.
    function test_SumCursor_JustInsideHorizon_AdvancesNormally() public {
        uint256 cursor = vw.timeSum();
        vm.warp(cursor + HORIZON - 1);

        vw.checkpoint();

        assertEq(vw.timeSum(), cursor + HORIZON, "cursor reaches the last walkable week");
        assertEq(vw.timeSum(), _nextBoundary(), "which is the next weekly boundary");
    }

    /// @dev Exactly 250 weeks past the cursor the walk reaches block.timestamp but cannot pass it: the cursor must
    ///      still move, to the next weekly boundary, with a zero point, and stay consistent on repeated checkpoints.
    function test_SumCursor_AtHorizon_FastForwards() public {
        uint256 cursor = vw.timeSum();
        vm.warp(cursor + HORIZON);

        vw.checkpoint();

        uint256 next = _nextBoundary();
        assertEq(vw.timeSum(), next, "cursor at the next weekly boundary");
        (uint256 bias, uint256 slope) = _sumPoint(next);
        assertEq(bias, 0, "zero bias");
        assertEq(slope, 0, "zero slope");

        vw.checkpoint();
        assertEq(vw.timeSum(), next, "repeated checkpoint keeps the cursor");
    }

    /// @dev One second past the horizon behaves like the boundary.
    function test_SumCursor_PastHorizon_FastForwards() public {
        uint256 cursor = vw.timeSum();
        vm.warp(cursor + HORIZON + 1);

        vw.checkpoint();

        assertEq(vw.timeSum(), _nextBoundary(), "cursor at the next weekly boundary");
    }

    /// @dev One second before the nominee horizon, the ordinary walk still reaches the next weekly boundary.
    ///      Passes before and after the fix; the sum is checkpointed separately so only the nominee is stale.
    function test_NomineeCursor_JustInsideHorizon_AdvancesNormally() public {
        vw.addNomineeEVM(n3, CHAIN_ID);
        uint256 cursor = vw.timeWeight(_hash(n3, CHAIN_ID));
        for (uint256 i = 0; i < 5; ++i) {
            vm.warp(block.timestamp + 50 * WEEK);
            vw.checkpoint();
        }
        vm.warp(cursor + HORIZON - 1);

        vw.checkpointNominee(_b32(n3), CHAIN_ID);

        assertEq(vw.timeWeight(_hash(n3, CHAIN_ID)), cursor + HORIZON, "last walkable week");
        assertEq(vw.timeWeight(_hash(n3, CHAIN_ID)), _nextBoundary(), "next weekly boundary");
    }

    /// @dev One second after the nominee horizon, fast-forward must reach the next boundary with a zero point.
    function test_NomineeCursor_PastHorizon_FastForwards() public {
        vw.addNomineeEVM(n3, CHAIN_ID);
        uint256 cursor = vw.timeWeight(_hash(n3, CHAIN_ID));
        for (uint256 i = 0; i < 5; ++i) {
            vm.warp(block.timestamp + 50 * WEEK);
            vw.checkpoint();
        }
        vm.warp(cursor + HORIZON + 1);

        vw.checkpointNominee(_b32(n3), CHAIN_ID);

        uint256 next = _nextBoundary();
        assertEq(vw.timeWeight(_hash(n3, CHAIN_ID)), next, "next weekly boundary");
        (uint256 bias, uint256 slope) = _weightPoint(n3, next);
        assertEq(bias, 0, "zero bias");
        assertEq(slope, 0, "zero slope");
    }

    /// @dev The per-nominee cursor at the horizon, with the sum cursor kept fresh by regular checkpoints.
    function test_NomineeCursor_AtHorizon_FastForwards() public {
        vw.addNomineeEVM(n3, CHAIN_ID);
        uint256 cursor = vw.timeWeight(_hash(n3, CHAIN_ID));

        // Keep the sum fresh; nobody touches n3
        for (uint256 i = 0; i < 5; ++i) {
            vm.warp(block.timestamp + 50 * WEEK);
            vw.checkpoint();
        }
        vm.warp(cursor + HORIZON);

        vw.checkpointNominee(_b32(n3), CHAIN_ID);

        uint256 next = _nextBoundary();
        assertEq(vw.timeWeight(_hash(n3, CHAIN_ID)), next, "nominee cursor at the next weekly boundary");
        (uint256 bias, uint256 slope) = _weightPoint(n3, next);
        assertEq(bias, 0, "zero bias");
        assertEq(slope, 0, "zero slope");
    }

    /// @dev Batch-votes 50/50 for n1 and n2 as `user`.
    function _batchVoteHalfHalf(address user) internal {
        bytes32[] memory accounts = new bytes32[](2);
        accounts[0] = _b32(n1);
        accounts[1] = _b32(n2);
        uint256[] memory chainIds = new uint256[](2);
        chainIds[0] = CHAIN_ID;
        chainIds[1] = CHAIN_ID;
        uint256[] memory weights = new uint256[](2);
        weights[0] = MAX_WEIGHT / 2;
        weights[1] = MAX_WEIGHT / 2;
        vm.prank(user);
        vw.voteForNomineeWeightsBatch(accounts, chainIds, weights);
    }

    /// @dev Relative weights are half each and the points match one contribution per nominee.
    function _assertHalfHalfAccounting(uint256 next, uint256 expectedBias, uint256 expectedSlope) internal view {
        (uint256 w1, ) = vw.nomineeRelativeWeight(_b32(n1), CHAIN_ID, next);
        (uint256 w2, ) = vw.nomineeRelativeWeight(_b32(n2), CHAIN_ID, next);
        assertEq(w1, 0.5e18, "n1 holds half");
        assertEq(w2, 0.5e18, "n2 holds half");
        assertLe(w1 + w2, 1e18, "relative weights sum to at most 1e18");

        (uint256 sumBias, uint256 sumSlope) = _sumPoint(next);
        assertEq(sumBias, 2 * expectedBias, "aggregate bias is both contributions");
        assertEq(sumSlope, 2 * expectedSlope, "aggregate slope is both contributions");
        (uint256 b1, uint256 s1) = _weightPoint(n1, next);
        (uint256 b2, uint256 s2) = _weightPoint(n2, next);
        assertEq(b1, expectedBias, "n1 bias");
        assertEq(s1, expectedSlope, "n1 slope");
        assertEq(b2, expectedBias, "n2 bias");
        assertEq(s2, expectedSlope, "n2 slope");
    }

    /// @dev Both cursors are at `next`, and a repeated checkpoint keeps the points.
    function _assertCursorsAndRepeatCheckpoint(uint256 next) internal {
        assertEq(vw.timeSum(), next, "sum cursor at the next boundary");
        assertEq(vw.timeWeight(_hash(n1, CHAIN_ID)), next, "n1 cursor at the next boundary");
        assertEq(vw.timeWeight(_hash(n2, CHAIN_ID)), next, "n2 cursor at the next boundary");

        (uint256 sumBias, uint256 sumSlope) = _sumPoint(next);
        (uint256 b1, uint256 s1) = _weightPoint(n1, next);
        vw.checkpoint();
        vw.checkpointNominee(_b32(n1), CHAIN_ID);
        (uint256 sumBiasAgain, uint256 sumSlopeAgain) = _sumPoint(next);
        (uint256 b1Again, uint256 s1Again) = _weightPoint(n1, next);
        assertEq(sumBiasAgain, sumBias, "aggregate bias preserved");
        assertEq(sumSlopeAgain, sumSlope, "aggregate slope preserved");
        assertEq(b1Again, b1, "n1 bias preserved");
        assertEq(s1Again, s1, "n1 slope preserved");
        assertEq(vw.timeSum(), next, "repeated checkpoint keeps the sum cursor");
    }

    /// @dev After a gap beyond the horizon with no checkpoint at all, a 50/50 batch vote must leave consistent
    ///      accounting: each nominee holds half, the aggregate is the sum of the two contributions, repeated
    ///      checkpoints keep it, and checkpoints written before the gap are untouched. Before the fix the second vote
    ///      overwrites the aggregate with its own contribution, so each nominee reads a relative weight of 1e18.
    function test_GapBeyondHorizon_BatchVote_ConsistentAccounting() public {
        vw.addNomineeEVM(n1, CHAIN_ID);
        vw.addNomineeEVM(n2, CHAIN_ID);

        // Activity before the gap leaves a non-zero historical checkpoint
        _lock(alice, 1_000 ether, MAXTIME);
        _vote(alice, n1, CHAIN_ID, MAX_WEIGHT);
        uint256 historicalTime = vw.timeSum();
        (uint256 historicalBias, uint256 historicalSlope) = _sumPoint(historicalTime);
        assertGt(historicalBias, 0, "historical checkpoint is non-zero");

        // No checkpoint of any kind for 300 weeks, then a 50/50 batch vote
        vm.warp(block.timestamp + 300 * WEEK);
        _lock(carol, 1_000 ether, MAXTIME);
        _batchVoteHalfHalf(carol);

        uint256 next = _nextBoundary();
        (uint256 expectedBias, uint256 expectedSlope) = _contribution(carol, MAX_WEIGHT / 2, next);
        assertGt(expectedBias, 0, "non-zero contribution");

        _assertHalfHalfAccounting(next, expectedBias, expectedSlope);
        _assertCursorsAndRepeatCheckpoint(next);

        // The historical checkpoint written before the gap is intact
        (uint256 hb, uint256 hs) = _sumPoint(historicalTime);
        assertEq(hb, historicalBias, "historical bias intact");
        assertEq(hs, historicalSlope, "historical slope intact");
    }

    /// @dev A nominee left without a checkpoint beyond the horizon while the sum stays fresh: alice votes for it, then
    ///      bob casts a zero vote for it. The zero vote must succeed and must not erase alice's contribution. Before the
    ///      fix the stale nominee cursor makes the zero vote overwrite the nominee point with zero while the aggregate
    ///      keeps alice's bias.
    function test_NomineeGapBeyondHorizon_ZeroVoteDoesNotEraseOtherVoter() public {
        vw.addNomineeEVM(n3, CHAIN_ID);

        // Keep the sum fresh for 300 weeks; nobody touches n3
        for (uint256 i = 0; i < 6; ++i) {
            vm.warp(block.timestamp + 50 * WEEK);
            vw.checkpoint();
        }

        _lock(alice, 1_000 ether, MAXTIME);
        _lock(bob, 1_000 ether, MAXTIME);
        _vote(alice, n3, CHAIN_ID, MAX_WEIGHT);
        uint256 next = _nextBoundary();
        (uint256 expectedBias, uint256 expectedSlope) = _contribution(alice, MAX_WEIGHT, next);

        // The zero vote succeeds
        _vote(bob, n3, CHAIN_ID, 0);

        // ...and alice's contribution survives it
        (uint256 bias, uint256 slope) = _weightPoint(n3, next);
        assertEq(bias, expectedBias, "alice's bias preserved");
        assertEq(slope, expectedSlope, "alice's slope preserved");
        (uint256 sumBias, ) = _sumPoint(next);
        assertEq(sumBias, expectedBias, "aggregate holds alice's bias");
        (uint256 w, ) = vw.nomineeRelativeWeight(_b32(n3), CHAIN_ID, next);
        assertEq(w, 1e18, "n3 holds the whole weight");
        assertEq(vw.timeWeight(_hash(n3, CHAIN_ID)), next, "n3 cursor at the next boundary");
    }

    // ----------------------------------------------------------------------------------------------
    // #27 / tokenomics #42 - nominee registration checks through the dispenser
    // ----------------------------------------------------------------------------------------------

    uint256 internal constant FOREIGN_CHAIN_ID = 10;

    function _vwWithDispenser() internal returns (VoteWeighting vwd, MockDispenser md) {
        md = new MockDispenser();
        vwd = new VoteWeighting(address(ve), address(md));
    }

    /// @dev EVM and non-EVM chains without a deposit processor are rejected.
    function test_AddNominee_NoDepositProcessor_Reverts() public {
        (VoteWeighting vwd, ) = _vwWithDispenser();

        vm.expectRevert(abi.encodeWithSignature("NoDepositProcessor(uint256)", FOREIGN_CHAIN_ID));
        vwd.addNomineeEVM(n1, FOREIGN_CHAIN_ID);

        uint256 nonEvmChainId = vwd.MAX_EVM_CHAIN_ID() + 1;
        vm.expectRevert(abi.encodeWithSignature("NoDepositProcessor(uint256)", nonEvmChainId));
        vwd.addNomineeNonEVM(keccak256("non-EVM target"), nonEvmChainId);
    }

    /// @dev EVM and non-EVM chains with a deposit processor are accepted. Passes before and after the change.
    function test_AddNominee_WithDepositProcessor_Succeeds() public {
        (VoteWeighting vwd, MockDispenser md) = _vwWithDispenser();
        uint256 nonEvmChainId = vwd.MAX_EVM_CHAIN_ID() + 1;
        md.setDepositProcessor(FOREIGN_CHAIN_ID, address(0xD10));
        md.setDepositProcessor(nonEvmChainId, address(0xD11));

        vwd.addNomineeEVM(n1, FOREIGN_CHAIN_ID);
        vwd.addNomineeNonEVM(keccak256("non-EVM target"), nonEvmChainId);
        assertEq(md.addCount(), 2, "both nominees added through the dispenser");
    }

    /// @dev The retainer is rejected under another chain Id, with that chain configured so only the retainer check can
    ///      fire.
    function test_AddNominee_RetainerOnForeignChain_Reverts() public {
        (VoteWeighting vwd, MockDispenser md) = _vwWithDispenser();
        md.setRetainer(_b32(n2));
        md.setDepositProcessor(FOREIGN_CHAIN_ID, address(0xD10));

        vm.expectRevert(abi.encodeWithSignature("RetainerOnForeignChain(bytes32,uint256)", _b32(n2), FOREIGN_CHAIN_ID));
        vwd.addNomineeEVM(n2, FOREIGN_CHAIN_ID);

        // Any other account on that chain is fine
        vwd.addNomineeEVM(n1, FOREIGN_CHAIN_ID);
    }

    /// @dev The retainer on this chain is accepted. Passes before and after the change.
    function test_AddNominee_RetainerOnOwnChain_Succeeds() public {
        (VoteWeighting vwd, MockDispenser md) = _vwWithDispenser();
        md.setRetainer(_b32(n2));
        md.setDepositProcessor(block.chainid, address(0xD12));

        vwd.addNomineeEVM(n2, block.chainid);
        assertEq(md.addCount(), 1, "retainer added on its own chain");
    }

    /// @dev Without a dispenser there are no registration checks. Passes before and after the change.
    function test_AddNominee_NoDispenser_SkipsChecks() public {
        vw.addNomineeEVM(n1, FOREIGN_CHAIN_ID);
        vw.addNomineeNonEVM(keccak256("non-EVM target"), vw.MAX_EVM_CHAIN_ID() + 1);
        assertEq(vw.getNumNominees(), 2, "both added");
    }
}
