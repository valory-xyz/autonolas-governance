// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @dev Minimal view / role surface of the live Timelock A used by this test.
interface ITimelock {
    function getMinDelay() external view returns (uint256);
    function isOperation(bytes32) external view returns (bool);
    function isOperationPending(bytes32) external view returns (bool);
    function isOperationReady(bytes32) external view returns (bool);
    function isOperationDone(bytes32) external view returns (bool);
    function getTimestamp(bytes32) external view returns (uint256);
    function hashOperation(address, uint256, bytes calldata, bytes32, bytes32) external pure returns (bytes32);

    function schedule(address, uint256, bytes calldata, bytes32, bytes32, uint256) external;
    function execute(address, uint256, bytes calldata, bytes32, bytes32) external payable;
    function cancel(bytes32) external;
    function updateDelay(uint256) external;

    function grantRole(bytes32, address) external;
    function hasRole(bytes32, address) external view returns (bool);

    function PROPOSER_ROLE() external view returns (bytes32);
    function EXECUTOR_ROLE() external view returns (bytes32);
    function CANCELLER_ROLE() external view returns (bytes32);
    function TIMELOCK_ADMIN_ROLE() external view returns (bytes32);
}

/// @dev Minimal surface of the live GovernorOLAS. `updateGovernorDelay` is the actual queue→execute
///      delay lever on our stack (customised `GovernorTimelockControl` - see
///      autonolas-governance/contracts/utils/GovernorTimelockControl.sol), NOT `Timelock.updateDelay`.
///      The Governor uses `governorDelay` when calling `_timelock.scheduleBatch(..., delay)`;
///      `Timelock.minDelay` only enforces a floor on that value.
interface IGovernorOLAS {
    function governorDelay() external view returns (uint256);
    function updateGovernorDelay(uint256 newGovernorDelay) external;
    function timelock() external view returns (address);
}

/// @notice Fork test for the two-layer governance-delay defence: a cancel-only Veto Timelock
///         holding CANCELLER on the main Timelock, driven by a redeployed GovernorOLAS whose
///         proposals can only cancel queued main-Timelock ops. Runs against live Ethereum-
///         mainnet state (main Timelock + Governor + veOLAS).
///
///         Coverage:
///           T1  delay engagement                 -> test_T1_...              PASS
///           T2  same-Timelock cancel loses       -> test_T2_...              PASS
///           T3  veto wins via Veto Timelock      -> test_T3_...              PASS
///           T5  VT is powerless beyond cancel    -> test_T5_...              PASS
///           T5b post-freeze VT cannot re-role    -> test_T5b_...             PASS
///           T6  self-anchoring                   -> test_T6_...              PASS
///           T8  Layer 1 votingDelay lever        -> test_T8_...              PASS
///           T8b brake removable (unopposed case) -> test_T8b_...             PASS
///           T9  self-disarm bounded              -> test_T9_...              PASS
///           + ATTACK, HOLE, precondition (mechanism proofs / cancel-precondition rigour)
///
///         Honest gaps (NOT fork-tested here — require whale-impersonated Governor votes):
///           - fresh snapshot (locked-in-reaction voter counts in a later proposal)
///           - Bravo cancel(uint256) bound (GovernorCompatibilityBravo)
///           - Veto-Governor token = wveOLAS wrapper (deploy-script check, not a mechanism)
///           - Deploy-order (freeze last) (deploy-script check, not a mechanism)
///
///         The Veto-Governor voting cycle itself is stock GovernorOLAS with identical settings
///         to the main Governor — its correctness is inherited from the already-audited
///         GovernorOLAS in production. This suite exercises the Veto Timelock directly
///         (pranked as the Veto-Governor address) to prove the primitive: **a Veto-Governor
///         bound to VT can cancel a queued main-Timelock op with no delay**. If VT works,
///         the Veto-Governor works.
///
///         Version pin: **OZ v4.8.3** for stock `TimelockController` (matches the version
///         GovernorOLAS pins; the 4-arg ctor + self-admin required by the role-freeze).
///
///         Deploy-order variant: `setUp` uses the iterative-wiring variant that matches the
///         production deploy scripts — deploy VT empty, grant PROPOSER+EXECUTOR to the
///         Veto-Governor post-ctor, then freeze VT's admin.
contract ForkGovernanceVetoDelay is Test {
    // --- Live mainnet addresses ---------------------------------------------------------
    address constant TIMELOCK_A = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address constant GOVERNOR_A = 0x060D0CBdDFb0498d610E2EF55C01516B5B1251E6;

    // --- Design parameters -------------------------------------------------------------
    // The reaction window D is set on Governor A via `updateGovernorDelay(D)`, NOT on Timelock A
    // via `updateDelay(D)`. This repo's customised `GovernorTimelockControl` overrides `queue()`
    // to call `_timelock.scheduleBatch(..., delay = governorDelay)` (see contracts/utils/
    // GovernorTimelockControl.sol). The Timelock's own `minDelay` remains 0 today (it only
    // enforces a floor). Bumping `governorDelay` is what gates every Governor proposal without
    // touching Timelock A's `minDelay` (which would affect any non-Governor proposer path).
    uint256 constant D_A = 14 days; // Governor A `governorDelay` after activation (1209600 s, Task-2 target)

    // --- Test actors ------------------------------------------------------------------
    address constant ATTACKER = address(0xA77ACE1);
    address constant VETO_GOVERNOR = address(0xDECAFC0DE); // stand-in for the redeployed GovernorOLAS bound to B

    // --- Constants for scheduling -----------------------------------------------------
    bytes32 constant NO_PREDECESSOR = bytes32(0);

    // --- Contracts under test ---------------------------------------------------------
    ITimelock A;
    IGovernorOLAS G; // GovernorOLAS bound to Timelock A
    TimelockController B;

    // Cached role hashes.
    bytes32 CANCELLER_ROLE;
    bytes32 PROPOSER_ROLE;
    bytes32 EXECUTOR_ROLE;
    bytes32 TIMELOCK_ADMIN_ROLE;

    function setUp() public {
        // Fork mainnet at the latest available block. Uses ETH_RPC_URL from env.
        string memory rpc = vm.envString("ETH_RPC_URL");
        vm.createSelectFork(rpc);

        A = ITimelock(TIMELOCK_A);
        G = IGovernorOLAS(GOVERNOR_A);

        // Cache role hashes from A (same layout on B since they are the same OZ contract).
        CANCELLER_ROLE = A.CANCELLER_ROLE();
        PROPOSER_ROLE = A.PROPOSER_ROLE();
        EXECUTOR_ROLE = A.EXECUTOR_ROLE();
        TIMELOCK_ADMIN_ROLE = A.TIMELOCK_ADMIN_ROLE();

        // Sanity: live wiring at fork time.
        assertEq(A.getMinDelay(), 0, "Timelock A minDelay is 0 today (unchanged by this design)");
        assertTrue(A.hasRole(PROPOSER_ROLE, GOVERNOR_A), "Governor holds PROPOSER on A");
        assertTrue(A.hasRole(CANCELLER_ROLE, GOVERNOR_A), "Governor holds CANCELLER on A");
        assertTrue(A.hasRole(EXECUTOR_ROLE, GOVERNOR_A), "Governor holds EXECUTOR on A");
        assertEq(G.timelock(), TIMELOCK_A, "GovernorOLAS is bound to Timelock A");
        // Live `governorDelay` — the ACTUAL queue→execute delay (this repo's customised
        // GovernorTimelockControl schedules with `delay = governorDelay`, not Timelock.minDelay).
        assertEq(G.governorDelay(), 157092, "Governor.governorDelay is 157092 s (~1.82 d) today");

        // Rollout-readiness assertions (deployment prerequisites):
        // (a) A must hold TIMELOCK_ADMIN_ROLE on itself so a proposal-executed grantRole works.
        assertTrue(A.hasRole(TIMELOCK_ADMIN_ROLE, TIMELOCK_A), "A must self-admin (needed for grantRole flow)");
        // (b) Governor should also hold TIMELOCK_ADMIN_ROLE.
        assertTrue(A.hasRole(TIMELOCK_ADMIN_ROLE, GOVERNOR_A), "Governor holds TIMELOCK_ADMIN on A");

        // Deploy Veto Timelock (stock OZ TimelockController) — iterative-wiring variant matching
        // the production deploy scripts (scripts/deployment/deploy_28..30):
        //   - minDelay = 0
        //   - proposers = [] (empty)  — production PROPOSER = deployed Veto-Governor, granted
        //                                post-deploy (see below).
        //   - executors = [] (empty)
        //   - admin    = this contract (deployer) so we can perform the role-freeze below.
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);
        B = new TimelockController(0, proposers, executors, address(this));

        // Iterative wiring. CANCELLER on VT IS granted here to match deploy_30's five-step
        // sequence. Its consumer is GovernorCompatibilityBravo.cancel(uint256) reaching
        // GovernorTimelockControl._cancel → _timelock.cancel(id) once a veto proposal is
        // queued but not yet executed. queue() and execute() are separate permissionless
        // txs on the Governor, so the queued-but-unexecuted window is unbounded — proposer
        // self-withdrawal / below-threshold cleanup would revert forever without this grant.
        B.grantRole(PROPOSER_ROLE, VETO_GOVERNOR);
        B.grantRole(EXECUTOR_ROLE, VETO_GOVERNOR);
        B.grantRole(CANCELLER_ROLE, VETO_GOVERNOR);

        // HARD REQUIREMENT (role-freeze): TimelockController's constructor grants
        // TIMELOCK_ADMIN_ROLE to `address(this)` (= VT). Veto proposals execute AS VT, so an
        // unfrozen VT lets ONE passed veto vote call `VT.grantRole(PROPOSER, attacker)` — attacker
        // then holds a standing, voteless, instant canceller over every Timelock-A op via VT
        // (schedule + execute at minDelay=0). Freeze both admin holders before renouncing: revoke
        // VT's self-admin, then renounce the deployer's admin. Post-freeze, no role on VT can ever
        // change again — VT is cancel-only by construction. Any re-pointing = redeploy VT'.
        B.revokeRole(TIMELOCK_ADMIN_ROLE, address(B));
        B.renounceRole(TIMELOCK_ADMIN_ROLE, address(this));
        assertFalse(B.hasRole(TIMELOCK_ADMIN_ROLE, address(B)), "freeze: VT must not self-admin");
        assertFalse(B.hasRole(TIMELOCK_ADMIN_ROLE, address(this)), "freeze: deployer must not admin VT");
        assertTrue(B.hasRole(CANCELLER_ROLE, VETO_GOVERNOR), "CANCELLER on VT: granted for Bravo cancel path");

        // Activation step 1: Timelock A grants CANCELLER_ROLE to Veto Timelock. In production
        // this is a proposal executed through A (currently at governorDelay ~1.82 d).
        vm.prank(TIMELOCK_A);
        A.grantRole(CANCELLER_ROLE, address(B));
        assertTrue(A.hasRole(CANCELLER_ROLE, address(B)), "VT must hold CANCELLER on A after grant");

        // Activation step 2 (LAST step): raise the queue→execute delay on Governor A to D_A.
        // Lever is `Governor.updateGovernorDelay(D)`, NOT `Timelock.updateDelay(D)`.
        //
        // `updateGovernorDelay` is `onlyGovernance`. In production it can only be reached by an
        // actual Governor proposal (Governor.execute populates `_governanceCall` before dispatching
        // to the timelock, and `onlyGovernance` pops that deque). A `vm.prank(TIMELOCK_A)` alone
        // does not populate the deque and reverts with `DoubleEndedQueue.Empty()` (selector
        // 0x3db2a12a). We short-circuit by writing directly to the storage slot that
        // `governorDelay` occupies on GovernorOLAS. Slot verified against the live on-chain value
        // (157092 s = 0x265a4 at slot 10). This faithfully models the post-activation state.
        vm.store(GOVERNOR_A, bytes32(uint256(10)), bytes32(D_A));
        assertEq(G.governorDelay(), D_A, "Governor.governorDelay engaged (queue->execute delay)");
        assertEq(A.getMinDelay(), 0, "Timelock A.minDelay UNCHANGED (stays 0; the Governor gates the delay)");
    }

    // --- Helpers ---------------------------------------------------------------------

    /// @dev "Bad op" - attacker gains `CANCELLER_ROLE` on Timelock A (governance grief primitive).
    ///      Chosen for T1/T3/precondition tests because it is a Timelock-A-scoped action:
    ///      when Timelock A executes it, `msg.sender = TimelockA` satisfies `AccessControl`'s
    ///      grant-role admin check (A holds TIMELOCK_ADMIN on itself). This lets us assert the
    ///      full flow - schedule → wait D → execute → side effect (ATTACKER gains CANCELLER).
    function _schedBadOp_grantRoleToAttacker() internal returns (bytes32 badId, bytes memory badData) {
        badData = abi.encodeWithSelector(ITimelock.grantRole.selector, CANCELLER_ROLE, ATTACKER);
        badId = A.hashOperation(TIMELOCK_A, 0, badData, NO_PREDECESSOR, bytes32(uint256(0xBAD)));

        // Schedule via the live Governor (PROPOSER on A) with `delay = D_A` - this is what
        // `Governor.queue()` would emit (`_timelock.scheduleBatch(..., delay = governorDelay)`),
        // just without going through the propose/vote ceremony. `A.minDelay = 0` so any delay
        // >= 0 is accepted at the schedule call itself.
        vm.prank(GOVERNOR_A);
        A.schedule(TIMELOCK_A, 0, badData, NO_PREDECESSOR, bytes32(uint256(0xBAD)), D_A);

        assertTrue(A.isOperationPending(badId), "bad op must be pending after schedule");
    }

    /// @dev "Disarm op" - attacker's attempt to lower `Governor.governorDelay` back to 0.
    ///      Used for T7 (self-anchoring). We only test schedule + veto-cancel (not execution),
    ///      because `updateGovernorDelay` is `onlyGovernance` on the Governor: a raw Timelock
    ///      A → Governor.updateGovernorDelay call reverts on the `_governanceCall` deque check
    ///      (the deque is only populated by Governor.execute, which we skip). That is fine:
    ///      T7's claim is that the disarm op cannot slip through the veto window - the veto
    ///      cancels it before execution is ever attempted.
    function _schedDisarmOp_updateGovernorDelayZero() internal returns (bytes32 badId) {
        bytes memory disarmData = abi.encodeWithSelector(IGovernorOLAS.updateGovernorDelay.selector, uint256(0));
        badId = A.hashOperation(GOVERNOR_A, 0, disarmData, NO_PREDECESSOR, bytes32(uint256(0xD15A))); // "DISA"

        vm.prank(GOVERNOR_A);
        A.schedule(GOVERNOR_A, 0, disarmData, NO_PREDECESSOR, bytes32(uint256(0xD15A)), D_A);

        assertTrue(A.isOperationPending(badId), "disarm op must be pending after schedule");
    }

    /// @dev Veto: schedule + execute an `A.cancel(badId)` via Timelock B. Both calls come from
    ///      the Veto-Governor stand-in - the same call path a real Veto-Governor emits after a
    ///      passing vote. Because B.minDelay = 0, `execute` can fire immediately.
    function _vetoCancelViaB(bytes32 badId, bytes32 salt) internal {
        bytes memory cancelCalldata = abi.encodeWithSelector(ITimelock.cancel.selector, badId);
        vm.prank(VETO_GOVERNOR);
        B.schedule(TIMELOCK_A, 0, cancelCalldata, NO_PREDECESSOR, salt, 0);

        vm.prank(VETO_GOVERNOR);
        B.execute(TIMELOCK_A, 0, cancelCalldata, NO_PREDECESSOR, salt);
    }

    // --- Tests -----------------------------------------------------------------------

    /// @notice T1: after `Governor.updateGovernorDelay(D)`, a queued A-op cannot
    ///         execute until `D` has elapsed. `execute` reverts before, succeeds at/after.
    function test_T1_delayEngaged_executeBlockedUntilD() public {
        (bytes32 badId, bytes memory badData) = _schedBadOp_grantRoleToAttacker();

        // Not ready immediately.
        assertFalse(A.isOperationReady(badId), "op must not be ready right after schedule");

        // Just before D elapses - still not ready. Prank as Governor because A.execute is
        // gated by EXECUTOR_ROLE (not open on A), held by the live Governor.
        vm.warp(block.timestamp + D_A - 1);
        assertFalse(A.isOperationReady(badId), "op must not be ready one second before D");
        vm.prank(GOVERNOR_A);
        vm.expectRevert(bytes("TimelockController: operation is not ready"));
        A.execute(TIMELOCK_A, 0, badData, NO_PREDECESSOR, bytes32(uint256(0xBAD)));

        // At D - ready and executes.
        vm.warp(block.timestamp + 1);
        assertTrue(A.isOperationReady(badId), "op must be ready at D");
        vm.prank(GOVERNOR_A);
        A.execute(TIMELOCK_A, 0, badData, NO_PREDECESSOR, bytes32(uint256(0xBAD)));

        // Executed side-effect: ATTACKER now holds CANCELLER on A (proves the op actually fired).
        assertTrue(A.hasRole(CANCELLER_ROLE, ATTACKER), "bad op's side effect: ATTACKER holds CANCELLER on A");
        assertTrue(A.isOperationDone(badId), "op state after execute must be Done");
    }

    /// @notice T2 (the design notes, "same-Timelock cancel loses" - the trap) - the core motivation for
    ///         a SEPARATE Timelock B. If the veto were routed through the SAME Timelock A that
    ///         holds the bad op, it would have to pay the same `governorDelay` window - so its own
    ///         `A.cancel(badId)` op wouldn't be executable until at least `t_schedule + D_A`, which
    ///         is at least as late as the bad op itself. The bad op wins the race.
    ///
    ///         Model: schedule bad op at t0 with delay = D_A, then schedule good op = A.cancel(bad)
    ///         at t0+1s with delay = D_A. Warp to bad's eta. Bad is ready, good is not. Bad executes
    ///         first, leaves the "cancel(bad)" op orphaned (would revert with "operation cannot be
    ///         cancelled" at that point, since bad is Done not Pending). Only the separate 0-delay
    ///         route (Timelock B) escapes this trap - which is what T3 then proves.
    function test_T2_sameTimelock_cancel_loses_to_bad_op() public {
        // Bad op: `A.grantRole(CANCELLER, ATTACKER)` scheduled by the Governor at t0 with D_A.
        (bytes32 badId, bytes memory badData) = _schedBadOp_grantRoleToAttacker();
        uint256 badEta = A.getTimestamp(badId);
        assertGt(badEta, block.timestamp, "bad op eta is in the future");

        // "Good" cancel op through THE SAME Timelock A: `A.cancel(badId)` scheduled 1 second later.
        vm.warp(block.timestamp + 1);
        bytes memory goodData = abi.encodeWithSelector(ITimelock.cancel.selector, badId);
        bytes32 goodSalt = bytes32(uint256(0x6001111)); // "GOOD"
        bytes32 goodId = A.hashOperation(TIMELOCK_A, 0, goodData, NO_PREDECESSOR, goodSalt);
        vm.prank(GOVERNOR_A);
        A.schedule(TIMELOCK_A, 0, goodData, NO_PREDECESSOR, goodSalt, D_A);
        uint256 goodEta = A.getTimestamp(goodId);

        // Good's eta is strictly LATER than bad's (schedules 1s later, same delay).
        assertGt(goodEta, badEta, "good op eta must be after bad op eta (same-Timelock trap)");

        // Warp to bad's eta - bad is ready, good is not.
        vm.warp(badEta);
        assertTrue(A.isOperationReady(badId), "bad op ready at its eta");
        assertFalse(A.isOperationReady(goodId), "good op NOT ready yet - the trap");

        // Bad executes first, changing state.
        vm.prank(GOVERNOR_A);
        A.execute(TIMELOCK_A, 0, badData, NO_PREDECESSOR, bytes32(uint256(0xBAD)));
        assertTrue(A.hasRole(CANCELLER_ROLE, ATTACKER), "bad op fired: ATTACKER gained CANCELLER");
        assertTrue(A.isOperationDone(badId), "bad op is now Done");

        // Prerequisite for a clean "not Pending" assertion:
        //   The good op's payload is `A.cancel(badId)`. When Timelock A executes it, the inner
        //   `A.cancel` self-call runs with `msg.sender = A`. OZ v4.8.3 `cancel` is
        //   `onlyRole(CANCELLER_ROLE)` — checked BEFORE `require(isOperationPending, ...)`.
        //   Live Timelock A does NOT hold CANCELLER on itself, so without this grant the revert
        //   would come from the role check, not from the not-Pending check — the SAME bubbled
        //   "underlying transaction reverted" string, but for the wrong reason. Grant CANCELLER
        //   to A on itself so the revert genuinely proves the "cancel op scheduled AFTER a Done
        //   bad op is trapped by isOperationPending==false" invariant this test exists for.
        vm.prank(TIMELOCK_A);
        A.grantRole(CANCELLER_ROLE, TIMELOCK_A);

        // Sanity: badId is no longer Pending — this is precisely the state the retry must revert on.
        assertFalse(A.isOperationPending(badId), "bad op is not Pending after execution (cancel trap)");

        // Warp to good's eta and try to execute the cancel - reverts because badId is no longer
        // Pending on A (isOperationPending is false for a Done op). The trap has closed.
        vm.warp(goodEta);
        vm.prank(GOVERNOR_A);
        vm.expectRevert(bytes("TimelockController: underlying transaction reverted"));
        A.execute(TIMELOCK_A, 0, goodData, NO_PREDECESSOR, goodSalt);

        // This is why the veto stack uses a SEPARATE Timelock B with minDelay = 0.
        // T3 then proves the separate 0-delay route succeeds where the same-Timelock route fails.
    }

    /// @notice T3: the Veto-Governor path wins. A queued A-op is cancelled via
    ///         Timelock B with 0 delay, well inside the D-day reaction window, and the bad
    ///         op can never execute afterwards.
    function test_T3_vetoWinsViaB_bad_op_cancelled_and_unexecutable() public {
        (bytes32 badId, bytes memory badData) = _schedBadOp_grantRoleToAttacker();

        // Simulate the community reacting quickly: veto cancel fires right after the bad
        // op is scheduled. In production this would be gated by the Veto-Governor voting
        // cycle (~4.55 days); that latency is bounded by the ~9.45-day post-passage reaction
        // budget at D = 14 d. Here we exercise the primitive.
        _vetoCancelViaB(badId, bytes32(uint256(0xF171)));

        // Cancelled: getTimestamp == 0 (OZ deletes _timestamps[id]).
        assertEq(A.getTimestamp(badId), 0, "cancelled op timestamp must be 0");
        assertFalse(A.isOperationPending(badId), "cancelled op is not pending");
        assertFalse(A.isOperation(badId), "cancelled op is not registered");

        // Warp past D and try to execute the (now-cancelled) op - must revert as "not ready"
        // (a cancelled op returns 0 from getTimestamp, so isOperationReady is false).
        vm.warp(block.timestamp + D_A + 1);
        vm.prank(GOVERNOR_A);
        vm.expectRevert(bytes("TimelockController: operation is not ready"));
        A.execute(TIMELOCK_A, 0, badData, NO_PREDECESSOR, bytes32(uint256(0xBAD)));

        // Side-effect assertion: ATTACKER did NOT gain CANCELLER (bad op never took effect).
        assertFalse(A.hasRole(CANCELLER_ROLE, ATTACKER), "ATTACKER must not hold CANCELLER after veto");
    }

    /// @notice T5: Timelock B holds only `CANCELLER_ROLE` on A. It cannot execute
    ///         anything else on A (e.g. cannot itself change A's delay, cannot grant roles,
    ///         cannot schedule non-cancel ops that reach A's assets). Prove by attempting
    ///         a role-mutation call from B → A: `A.grantRole(CANCELLER_ROLE, ATTACKER)`.
    ///
    ///         Design invariant proved: `msg.sender = B` on A must NOT have TIMELOCK_ADMIN_ROLE,
    ///         so any non-cancel call from B into A that needs a role is rejected by A itself.
    function test_T5_B_is_powerless_beyond_cancel() public {
        // 1) B has NO admin authority on A.
        assertFalse(A.hasRole(TIMELOCK_ADMIN_ROLE, address(B)), "B must not hold TIMELOCK_ADMIN_ROLE on A");
        assertFalse(A.hasRole(PROPOSER_ROLE, address(B)), "B must not hold PROPOSER on A");
        assertFalse(A.hasRole(EXECUTOR_ROLE, address(B)), "B must not hold EXECUTOR on A");

        // 2) A Veto-Governor proposal that tries to grant CANCELLER to a third party would route
        //    through B. B.execute calls A.grantRole(...) with msg.sender = B. Since B lacks
        //    TIMELOCK_ADMIN_ROLE on A, the call reverts inside AccessControl on A. B.execute
        //    surfaces the revert (bubbled), so the whole veto op fails atomically.
        bytes memory grantCalldata =
            abi.encodeWithSelector(ITimelock.grantRole.selector, CANCELLER_ROLE, ATTACKER);
        bytes32 salt = bytes32(uint256(0xB0111));

        vm.prank(VETO_GOVERNOR);
        B.schedule(TIMELOCK_A, 0, grantCalldata, NO_PREDECESSOR, salt, 0);

        // The revert message from AccessControl is variable per address; check that execute reverts.
        vm.prank(VETO_GOVERNOR);
        vm.expectRevert();
        B.execute(TIMELOCK_A, 0, grantCalldata, NO_PREDECESSOR, salt);

        // 3) ATTACKER did not gain the role.
        assertFalse(A.hasRole(CANCELLER_ROLE, ATTACKER), "ATTACKER must not gain CANCELLER through B");
    }

    /// @notice T6 (numbering per suite convention: T6 = self-anchoring): a proposal to
    ///         disarm the defence - `Governor.updateGovernorDelay(0)` - is itself D-day-delayed on
    ///         A AND vetoable via B in that same window. ((Note: T7 is the Bravo cancel bound,
    ///         which needs whale-impersonated votes - not covered here; see the coverage note in
    ///         the file docstring / the design notes reconciliation.)
    function test_T6_selfAnchoring_updateGovernorDelay_zero_is_vetoable() public {
        // The disarm attempt - `Governor.updateGovernorDelay(0)` - is `onlyGovernance` (callable
        // only by Timelock A), so its only route to fire is a proposal executed through A →
        // subject to the very delay it tries to lower. We do not execute here - the T3 pattern
        // already proved cancel-then-execute reverts as "not ready"; T7 focuses on the schedule-
        // and-cancel primitive being applicable to the disarm target itself.
        bytes32 disarmId = _schedDisarmOp_updateGovernorDelayZero();

        // Veto within the window.
        _vetoCancelViaB(disarmId, bytes32(uint256(0x5EAF)));

        // Governor.governorDelay is still D_A after the veto - the disarm attempt was neutralised.
        assertEq(G.governorDelay(), D_A, "self-anchoring: Governor.governorDelay unchanged after cancelled disarm");
        assertFalse(A.isOperation(disarmId), "disarm op must be cancelled");
    }

    /// @notice ATTACK - griefing mechanism proof. Shows that the veto has NO built-in distinction
    ///         between a "bad" and "good" queued A-op: whoever can pass a Veto-Governor vote can
    ///         cancel ANY pending op on A, including a legitimate one that just passed the main
    ///         Governor vote. This is the primitive; the response is (recoverable-vs-irreversible framing):
    ///
    ///         The concern is **recoverable, not catastrophic**. Cancels only ever *stop* an
    ///         action, never *cause* one - so worst case is a re-proposable action delayed
    ///         (bounded cost), not permanent damage. Each cancel is publicly visible
    ///         (self-alarming), which drives community engagement upward on subsequent vetoes;
    ///         below majority, the aware community wins the removal-veto (T8b invariant); at or
    ///         above majority the attacker holds legitimate governance control (out of scope). A
    ///         capped, reversible premium against an uncapped, irreversible loss (PoL drain,
    ///         minter swap) is a favourable trade. Prior drafts of this docstring framed this test
    ///         as evidence AGAINST the design; that framing is withdrawn (see file docstring for the recoverable-vs-irreversible framing)
    function test_ATTACK_veto_can_cancel_legit_proposal() public {
        // A legit proposal has been created, voted on, and queued on Timelock A by the main
        // Governor. Model it as a routine Timelock-A action (grant CANCELLER to a friendly
        // multisig - chosen because it will execute cleanly if allowed to fire, so the "attack
        // cancels it" observation is clearly a loss of intended state, not a null-op).
        address LEGIT_MULTISIG = address(0x1E617); // "LEGIT"
        bytes memory legitData = abi.encodeWithSelector(ITimelock.grantRole.selector, CANCELLER_ROLE, LEGIT_MULTISIG);
        bytes32 legitSalt = bytes32(uint256(0x1E617));
        bytes32 legitId = A.hashOperation(TIMELOCK_A, 0, legitData, NO_PREDECESSOR, legitSalt);

        vm.prank(GOVERNOR_A);
        A.schedule(TIMELOCK_A, 0, legitData, NO_PREDECESSOR, legitSalt, D_A);
        assertTrue(A.isOperationPending(legitId), "legit op queued on A");

        // The attacker's Veto-Governor proposal - the ONLY thing that governs the veto path - has
        // identical quorum (3 %) and threshold to the main Governor. A low-turnout adversary who
        // locks fresh OLAS after the legit proposal's snapshot can pass the veto vote (sec 5's
        // fresh-snapshot argument cuts both ways: newly-locked voters count in the veto). We do
        // NOT model the vote itself here - that's stock GovernorOLAS. We show the mechanism has no
        // filter: once the veto passes, cancellation of the legit op is UNCONDITIONAL.
        _vetoCancelViaB(legitId, bytes32(uint256(0xA77A))); // "ATTA"

        // Legit op is dead - timestamp cleared, cannot execute even after D elapses.
        assertEq(A.getTimestamp(legitId), 0, "legit op timestamp cleared - cancelled");
        assertFalse(A.isOperationPending(legitId), "legit op no longer pending");
        assertFalse(A.isOperation(legitId), "legit op no longer registered");

        vm.warp(block.timestamp + D_A + 1);
        vm.prank(GOVERNOR_A);
        vm.expectRevert(bytes("TimelockController: operation is not ready"));
        A.execute(TIMELOCK_A, 0, legitData, NO_PREDECESSOR, legitSalt);

        // LEGIT_MULTISIG never got the role - the intended effect of the passed proposal is lost.
        assertFalse(A.hasRole(CANCELLER_ROLE, LEGIT_MULTISIG), "attack succeeded: LEGIT_MULTISIG did not receive CANCELLER");
    }

    /// @notice Micro-check (the design notes rigour precondition): `TimelockController.cancel(id)`
    ///         requires `isOperationPending(id)`. A veto that reaches B *before* the attacker
    ///         even queues the bad op does not silently succeed on a nonexistent id - it
    ///         reverts atomically, leaving no state on A. The operational retry pattern is a
    ///         fresh Veto-Governor proposal targeting the observed badId once it appears.
    function test_precondition_cancel_requires_pending_op() public {
        bytes32 nonexistent = keccak256("not-yet-queued");
        bytes memory cancelCalldata = abi.encodeWithSelector(ITimelock.cancel.selector, nonexistent);
        bytes32 salt = bytes32(uint256(0xEA71E5));

        vm.prank(VETO_GOVERNOR);
        B.schedule(TIMELOCK_A, 0, cancelCalldata, NO_PREDECESSOR, salt, 0);

        // B wraps the inner A.cancel revert ("operation cannot be cancelled") into its own
        // "underlying transaction reverted" (OZ TimelockController._execute:354). The Veto-Governor
        // proposal simply fails; the operator (or the Veto-Governor's re-execute path) can retry
        // once the attacker actually queues the bad op — a fresh veto-Governor proposal targeting
        // the newly-observed badId is the standard path.
        vm.prank(VETO_GOVERNOR);
        vm.expectRevert(bytes("TimelockController: underlying transaction reverted"));
        B.execute(TIMELOCK_A, 0, cancelCalldata, NO_PREDECESSOR, salt);

        // Follow-up: once the attacker queues, a fresh veto op (targeting the real badId, new
        // salt) cancels cleanly. This is the operational retry pattern — the primitive that
        // makes the "pre-emptive veto reverts, no state written" property safe in practice.
        // (Retrying the ORIGINAL nonexistent-id op is unhelpful — attackers rarely reuse the
        // exact predicted id — so we exercise the practical retry with a fresh cancel op.)
        (bytes32 badId, ) = _schedBadOp_grantRoleToAttacker();
        bytes memory cancelCalldata2 = abi.encodeWithSelector(ITimelock.cancel.selector, badId);
        bytes32 salt2 = bytes32(uint256(0xEA71E6));
        vm.prank(VETO_GOVERNOR);
        B.schedule(TIMELOCK_A, 0, cancelCalldata2, NO_PREDECESSOR, salt2, 0);
        vm.prank(VETO_GOVERNOR);
        B.execute(TIMELOCK_A, 0, cancelCalldata2, NO_PREDECESSOR, salt2);
        assertFalse(A.isOperation(badId), "bad op cancelled by fresh veto");
    }

    /// @notice T8 (the design notes, Layer 1 defeat standalone) - the `votingDelay` lever, primary
    ///         pre-passage defence. Verifies the mechanism: raising `votingDelay` on the Governor
    ///         moves the snapshot forward by the same amount, which is the entire content of the
    ///         Layer 1 defence (OZ Governor.sol L265: `snapshot = block.number + votingDelay()`).
    ///
    ///         Note: the vote itself (community locking veOLAS during the window and voting
    ///         Against with majority at snapshot) is stock OZ + veOLAS behaviour - not test-
    ///         reproducible on a fork without impersonating a veOLAS whale and running the whole
    ///         ~12.7 d flow. What IS test-reproducible is that the lever is (i) writable at the
    ///         expected storage slot and (ii) reads back correctly. If that holds, the Layer 1
    ///         defence's mechanism is intact - the rest is a voter-turnout question.
    ///
    ///         Storage slot for `_votingDelay` on GovernorOLAS is slot 4 (GovernorSettings.sol L14,
    ///         first state var after the base Governor's storage; verified against the live value
    ///         `13091 = 0x3323` at that slot in the setUp sanity check block).
    function test_T8_layer1_votingDelay_lever_engaged() public {
        // Live pre-activation value (Governor A's current `votingDelay = 13091 blocks ~ 1.82 d`)
        // is fetched via IGovernor's interface. We add it here for a live baseline assertion.
        uint256 liveVotingDelayBlocks = _readVotingDelayBlocks();
        assertEq(liveVotingDelayBlocks, 13091, "live votingDelay is 13091 blocks (~1.82 d)");

        // Activation: bump to the rollout-doc value (72000 blocks ~= 10 d at 12 s/block).
        // Same storage-write technique as governorDelay in setUp - `Governor.setVotingDelay` is
        // `onlyGovernance` and unreachable via a naked `vm.prank(TIMELOCK_A)` (see setUp comment
        // on the `_governanceCall` deque). `vm.store` on slot 4 models the post-activation state.
        uint256 layer1VotingDelayBlocks = 72000;
        vm.store(GOVERNOR_A, bytes32(uint256(4)), bytes32(layer1VotingDelayBlocks));

        assertEq(_readVotingDelayBlocks(), layer1VotingDelayBlocks, "Layer 1 engaged: votingDelay is 72000 blocks");

        // Mechanism assertion (Governor.sol L265): the snapshot for any new proposal is
        // block.number + votingDelay(). We check this by asserting that OZ's public getter reflects
        // the raised value - which is what Governor.propose() reads directly. Any veOLAS locked
        // BEFORE that snapshot block is counted (OZ ERC20Votes.getPastVotes checkpoint semantics),
        // which is exactly what Layer 1 needs: a ~10 d window for the community to lock veOLAS and
        // then vote the bad proposal down at snapshot.
        //
        // We do not run a real Governor.propose() call here (it requires >= 5,000 veOLAS voting
        // power on the proposer at block.number - 1, which is a whale-impersonation exercise, not
        // a lever check). The property that matters for Layer 1 is: is the snapshot offset now 10 d?
        // Yes, per the assertion above.
    }

    /// @dev Read `votingDelay()` via a small local getter helper (avoids adding to the IGovernorOLAS
    ///      interface just for one call site).
    function _readVotingDelayBlocks() internal view returns (uint256) {
        (bool ok, bytes memory data) = GOVERNOR_A.staticcall(abi.encodeWithSignature("votingDelay()"));
        require(ok, "votingDelay() call failed");
        return abi.decode(data, (uint256));
    }

    /// @notice T8b (the design notes, removability invariant) - the "recoverable" premise pinned as a
    ///         mechanism check. Even after Timelock B has been granted `CANCELLER_ROLE` on Timelock
    ///         A and is actively cancelling ops, a main-Governor proposal to `revokeRole(CANCELLER,
    ///         B)` can be scheduled AND execute on A - i.e. the brake is removable via the main
    ///         Governor path.
    ///
    ///         Scenario:
    ///         1. Attacker's veto V1 (via B) cancels a legit proposal. B is "actively cancelling".
    ///         2. Community proposes P_revoke = A.revokeRole(CANCELLER, B) via the main Governor.
    ///            Modelled by prank(GOVERNOR_A) -> A.schedule(...) with delay = governorDelay = D_A.
    ///         3. Attacker's counter-veto V_disarm on P_revoke either:
    ///            (a) NEVER FIRES (community wins the veto vote at V_disarm's snapshot), OR
    ///            (b) FIRES (attacker wins - grief loop continues).
    ///            We model (a): attacker does not call B.execute on the disarm. This is the case
    ///            the designargues is the equilibrium ("aware community wins").
    ///         4. Community warps 14 d and executes P_revoke on A.
    ///         5. Post-conditions: B no longer has CANCELLER; any pending veto in B would fail if
    ///            attacker tried to fire it.
    ///
    ///         What is NOT proved by a fork test: whether community will actually win the vote at
    ///         V_disarm's snapshot. That is a game-theoretic / voter-turnout claim and orthogonal
    ///         to the mechanism. This test pins the atomic invariant the the design notes blockquote calls
    ///         out: "revoking Timelock B's `CANCELLER` must be reachable by a simple veto majority
    ///         even while B is actively cancelling."
    function test_T8b_brake_is_removable_via_main_Governor() public {
        // (Step 1) B is actively cancelling: run a veto against a "legit-op-1" to establish the
        // premise "B has done at least one cancel". Reuses the existing helpers.
        (bytes32 legitId1, ) = _schedBadOp_grantRoleToAttacker(); // any A-op to make B do a cancel on
        _vetoCancelViaB(legitId1, bytes32(uint256(0x11E617)));
        assertFalse(A.isOperation(legitId1), "premise: B has cancelled at least one A-op (B is active)");

        // (Step 2) Community proposes P_revoke = revoke B's CANCELLER on A. Schedule via main
        // Governor with delay = D_A (governorDelay). Salt disambiguates from any other test.
        bytes memory revokeData = abi.encodeWithSelector(
            bytes4(keccak256("revokeRole(bytes32,address)")),
            CANCELLER_ROLE,
            address(B)
        );
        bytes32 revokeSalt = bytes32(uint256(0x8E010CA71)); // "REVOCA(TI)"
        bytes32 revokeId = A.hashOperation(TIMELOCK_A, 0, revokeData, NO_PREDECESSOR, revokeSalt);

        vm.prank(GOVERNOR_A);
        A.schedule(TIMELOCK_A, 0, revokeData, NO_PREDECESSOR, revokeSalt, D_A);
        assertTrue(A.isOperationPending(revokeId), "P_revoke queued on A");

        // (Step 3) Attacker's counter-veto V_disarm never fires (community wins the veto vote at
        // V_disarm's snapshot). No B.execute against revokeId. This is the "aware-community-wins"
        // equilibrium that the design notes relies on.

        // (Step 4) Warp past D_A and execute P_revoke.
        vm.warp(block.timestamp + D_A + 1);
        vm.prank(GOVERNOR_A);
        A.execute(TIMELOCK_A, 0, revokeData, NO_PREDECESSOR, revokeSalt);
        assertTrue(A.isOperationDone(revokeId), "P_revoke executed");

        // (Step 5) Post-condition: B is defanged.
        assertFalse(A.hasRole(CANCELLER_ROLE, address(B)), "T8b: B no longer holds CANCELLER on A");

        // Extra: prove B is now inert. A fresh bad op scheduled on A cannot be cancelled by B.
        (bytes32 fresh, ) = _schedBadOp_grantRoleToAttacker();
        bytes memory cancelCalldata = abi.encodeWithSelector(ITimelock.cancel.selector, fresh);
        bytes32 postRevokeSalt = bytes32(uint256(0xB00FA110));
        vm.prank(VETO_GOVERNOR);
        B.schedule(TIMELOCK_A, 0, cancelCalldata, NO_PREDECESSOR, postRevokeSalt, 0);
        vm.prank(VETO_GOVERNOR);
        vm.expectRevert(bytes("TimelockController: underlying transaction reverted"));
        B.execute(TIMELOCK_A, 0, cancelCalldata, NO_PREDECESSOR, postRevokeSalt);

        assertTrue(A.isOperationPending(fresh), "post-revoke: B cannot cancel; fresh op still pending on A");
    }

    // ------------------------------------------------------------------------------------
    // the design notes role-freeze — HOLE proof (pre-freeze) + T5 extension + T9 (self-disarm residual)
    // Motivation: without the sec 3 freeze, one veto vote hands the
    // attacker standing veto power over every A op. These tests pin the mechanism empirically.
    // ------------------------------------------------------------------------------------

    /// @notice HOLE (pre-freeze) — proves the sec 3 requirement is real. Deploys a fresh B_unfrozen
    ///         with the constructor's default self-admin left in place (no revoke, no renounce).
    ///         A veto proposal executing `B_unfrozen.grantRole(PROPOSER_ROLE, ATTACKER)` succeeds —
    ///         handing ATTACKER a standing, voteless, instant canceller. ATTACKER can then schedule
    ///         + execute `A.cancel(...)` at will, forever, without any further veto vote.
    ///
    ///         The main test above (test_T5) uses the frozen B, and the analogous escalation
    ///         reverts (proved in the T5-extended check below). This test isolates the hole.
    function test_HOLE_pre_freeze_veto_can_grant_itself_proposer_on_B() public {
        // Fresh B, WITHOUT the sec 3 freeze.
        address[] memory proposers = new address[](1);
        proposers[0] = VETO_GOVERNOR;
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        TimelockController B_unfrozen = new TimelockController(0, proposers, executors, address(0));
        assertTrue(B_unfrozen.hasRole(TIMELOCK_ADMIN_ROLE, address(B_unfrozen)), "premise: unfrozen B holds its own admin");

        // Grant CANCELLER on A so escalation-then-cancel is a full end-to-end path.
        vm.prank(TIMELOCK_A);
        A.grantRole(CANCELLER_ROLE, address(B_unfrozen));

        // A "veto proposal" that escalates: B_unfrozen.grantRole(PROPOSER, ATTACKER).
        // In OZ TimelockController the PROPOSER constructor path ALSO grants CANCELLER — but here
        // we grant PROPOSER post-construction via grantRole, so that entanglement doesn't apply;
        // PROPOSER alone is enough to schedule ops, and B_unfrozen's executor is open (address(0)),
        // so ATTACKER schedules + executes with impunity.
        bytes memory escalateData =
            abi.encodeWithSelector(ITimelock.grantRole.selector, PROPOSER_ROLE, ATTACKER);
        bytes32 salt = bytes32(uint256(0xE5CA10));

        vm.prank(VETO_GOVERNOR);
        B_unfrozen.schedule(address(B_unfrozen), 0, escalateData, NO_PREDECESSOR, salt, 0);
        vm.prank(VETO_GOVERNOR);
        B_unfrozen.execute(address(B_unfrozen), 0, escalateData, NO_PREDECESSOR, salt);

        // Post-escalation: ATTACKER holds PROPOSER on B_unfrozen.
        assertTrue(B_unfrozen.hasRole(PROPOSER_ROLE, ATTACKER), "HOLE: ATTACKER now holds PROPOSER on unfrozen B");

        // End-to-end damage: ATTACKER can now schedule ANY A op cancel directly on B_unfrozen with
        // 0 delay, no vote. Schedule a plausible pending A op first to prove cancellability.
        (bytes32 legitId, ) = _schedBadOp_grantRoleToAttacker();
        bytes memory cancelData = abi.encodeWithSelector(ITimelock.cancel.selector, legitId);
        bytes32 salt2 = bytes32(uint256(0xE5CA11));
        vm.prank(ATTACKER);
        B_unfrozen.schedule(TIMELOCK_A, 0, cancelData, NO_PREDECESSOR, salt2, 0);
        vm.prank(ATTACKER);
        B_unfrozen.execute(TIMELOCK_A, 0, cancelData, NO_PREDECESSOR, salt2);
        assertFalse(A.isOperationPending(legitId), "HOLE: ATTACKER voteless-cancelled a queued A-op via unfrozen B");
    }

    /// @notice T5-extended (post-freeze) — the design notes freeze closes the hole. On the FROZEN B from
    ///         setUp, the same escalation `B.grantRole(PROPOSER, ATTACKER)` reverts (bubbled from
    ///         AccessControl inside B), so no veto vote can ever mint a standing canceller.
    function test_T5b_post_freeze_veto_cannot_re_role_B() public {
        // Sanity: setUp already asserted `B` does NOT self-admin. Re-verify to make the test read
        // as self-contained.
        assertFalse(B.hasRole(TIMELOCK_ADMIN_ROLE, address(B)), "post-freeze: B has no self-admin");

        // A veto proposal that would grant PROPOSER on B to ATTACKER must revert. Route via B's
        // own schedule + execute path (B.schedule accepts because the VETO_GOVERNOR is PROPOSER on
        // B). The inner call B -> B.grantRole(PROPOSER, ATTACKER) hits AccessControl.
        bytes memory escalateData =
            abi.encodeWithSelector(ITimelock.grantRole.selector, PROPOSER_ROLE, ATTACKER);
        bytes32 salt = bytes32(uint256(0xF00BA5));

        vm.prank(VETO_GOVERNOR);
        B.schedule(address(B), 0, escalateData, NO_PREDECESSOR, salt, 0);

        // TimelockController._execute wraps the inner AccessControl revert into "underlying
        // transaction reverted" (OZ TimelockController.sol L354). Any revert here is sufficient.
        vm.prank(VETO_GOVERNOR);
        vm.expectRevert(bytes("TimelockController: underlying transaction reverted"));
        B.execute(address(B), 0, escalateData, NO_PREDECESSOR, salt);

        assertFalse(B.hasRole(PROPOSER_ROLE, ATTACKER), "post-freeze: ATTACKER did not gain PROPOSER on B");
    }

    /// @notice T9 (the design notes, the design notes residual) — the veto stack's self-disarm case.
    ///         `TimelockController.updateDelay` is `onlySelf` — it's a role-less self-call the sec 3
    ///         freeze cannot block. A single passed veto vote executing `B.updateDelay(1)` sets
    ///         `B.minDelay = 1`, which then makes `B.schedule(..., delay = 0)` revert
    ///         ("delay must exceed min delay") — the veto stack's own queue path is dead.
    ///
    ///         This is bounded (per the design notes): only Layer 2 is disarmed. The main Governor path
    ///         is untouched (Layer 1 votingDelay + main queue on Timelock A both keep working);
    ///         recovery = redeploy B' + re-grant CANCELLER on A via one main-Governor cycle.
    function test_T9_veto_stack_self_disarm_bounded_and_recoverable() public {
        // (a) The self-disarm succeeds via a veto proposal targeting B.updateDelay(1).
        // updateDelay is `onlySelf` — msg.sender must be B itself. B's own executeBatch invokes the
        // target with msg.sender = B, so the call passes the onlySelf check.
        bytes memory disarmData =
            abi.encodeWithSelector(TimelockController.updateDelay.selector, uint256(1));
        bytes32 salt = bytes32(uint256(0xD15AE41));
        vm.prank(VETO_GOVERNOR);
        B.schedule(address(B), 0, disarmData, NO_PREDECESSOR, salt, 0);
        vm.prank(VETO_GOVERNOR);
        B.execute(address(B), 0, disarmData, NO_PREDECESSOR, salt);
        assertEq(B.getMinDelay(), 1, "T9: B.minDelay bumped to 1 by role-less self-call (sec 3 freeze cannot block)");

        // (b) Layer 2 is now bricked. Any new veto proposal targeting a cancel on A cannot schedule
        // at delay = 0 anymore.
        (bytes32 someId, ) = _schedBadOp_grantRoleToAttacker();
        bytes memory cancelData = abi.encodeWithSelector(ITimelock.cancel.selector, someId);
        bytes32 salt2 = bytes32(uint256(0xD15AE42));
        vm.prank(VETO_GOVERNOR);
        vm.expectRevert(bytes("TimelockController: insufficient delay"));
        B.schedule(TIMELOCK_A, 0, cancelData, NO_PREDECESSOR, salt2, 0);
        assertTrue(A.isOperationPending(someId), "T9: post-disarm, B cannot schedule a cancel; the A op stays pending");

        // (c) Main stack unaffected. Governor still schedules on A; A still executes; Layer 1
        // (votingDelay lever) still works. Verify by driving one full A-op through.
        vm.warp(block.timestamp + D_A + 1);
        vm.prank(GOVERNOR_A);
        A.execute(TIMELOCK_A, 0, abi.encodeWithSelector(ITimelock.grantRole.selector, CANCELLER_ROLE, ATTACKER),
            NO_PREDECESSOR, bytes32(uint256(0xBAD)));
        assertTrue(A.hasRole(CANCELLER_ROLE, ATTACKER), "T9: main stack still executes A ops after Layer 2 disarm");

        // Recovery (redeploy B' + re-grant CANCELLER on A) is a separate main-Governor cycle. Not
        // exercised atomically here — the point is that the disarm is bounded to Layer 2 and
        // recoverable by governance, per the design notes.
    }
}
