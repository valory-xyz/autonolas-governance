# Autonolas Governance — Fix Verification: `VoteWeighting.removeNominee` checkpoint-DoS (internal21)

Releasing-audit verification of **PR #215**
(`fix(VoteWeighting): reconcile removeNominee accounting to close checkpoint DoS`),
branch `fix/voteweighting-removenominee-dos` @ `a22490e`, base `main` @ `a7f6189`.

The review was performed by hand on the contract code and re-ran the shipped test
suite firsthand. This is a targeted verification that the fix (a) closes the
`internal20` "Findings to fix" that live in `VoteWeighting.sol`, (b) is correct and
complete, and (c) introduces no regression.

> **Verified commit / branch drift.** This verification is pinned to `a22490e` — the
> commit that contains the accounting fix. All file/line references below are relative
> to `a22490e`. The PR branch has since advanced to `8326d36` with additional commits;
> the accounting fix verified here is **byte-identical** at the branch tip (only
> relocated by later comment/reorder edits), but the branch now also carries an
> **unrelated functional change** that this verification does **not** cover. See
> §5 (Subsequent changes) before merging.

## Scope

Diff stats below are the verified snapshot at `a22490e` (vs base `a7f6189`); the branch
tip `8326d36` differs — see §5.

| File | Change |
|---|---|
| `contracts/VoteWeighting.sol` | +53 / −21 — the fix |
| `test/forge/VoteWeighting.t.sol` | +481 — 17 unit tests (incl. the DoS regression) |
| `test/forge/ForkVoteWeighting.t.sol` | +116 — mainnet-fork tests |
| `contracts/test/VoteWeightingFuzzing.sol` | +48 / −16 — echidna harness |

This is a **plain, non-upgradeable redeploy of `VoteWeighting`** with security fixes
only — no proxy refactor and no `MAX_NUM_NOMINEES` cap (both correctly out of scope
here). Because it is a fresh redeploy, the contract starts with no accumulated
checkpoint drift, so the added saturating-subtraction guards act purely as defense
in depth.

## 1. Findings closed

Maps to `internal20` §1 (F-numbers) and `docs/Vulnerabilities_list_governance.md`
(vuln-list numbers, as the code comments reference).

| internal20 | vuln-list | Item | Fix in PR #215 | Status |
|---|---|---|---|---|
| F-6 | #8 / #11 | `removeNominee` leaves a dangling slope + retains `changesSum` entries → over-decays the aggregate → the weekly checkpoint walk can underflow and revert permanently (also halts `Dispenser.nomineeRelativeWeightWrite`) | 3-part reconciliation (below) | **CLOSED** |
| F-3 | #18 | `_nomineeRelativeWeight` does not cap the returned weight at `1e18` | `if (weight > 1e18) { weight = 1e18; }` (`:439–441`) | **CLOSED** |
| F-4 | #19 | `removeNominee` last-element guard `(numNominees > 1)` re-populates `mapNomineeIds` for the just-removed nominee when it is the last element | guard changed to `if (id != numNominees)` (`:664`) | **CLOSED** |
| F-5 | #20 | `revokeRemovedNomineeVotingPower` mutates slope without first advancing the checkpoint → gauge-weight drift | aggregate writes **removed** from `revoke` (below) | **CLOSED (superseded)** |
| F-9 | #11 | `removeNominee` emits `OwnerOnly` with transposed arguments | `revert OwnerOnly(msg.sender, owner);` (`:599`) | **CLOSED (cosmetic)** |

`internal20` explicitly **rejected** the documented "ask voters to revoke before
removal" operational workaround for F-6 as insufficient for a re-audit, and asked for
the drift to be eliminated *at the source* inside `removeNominee`. PR #215 does exactly
that.

## 2. Fix correctness

### 2.1 The DoS root (F-6 / #8) — 3-part reconciliation

**(a) Saturating guard on both checkpoint walkers.** `_getSum` (`:239`) and
`_getWeight` (`:280`) replace `pt.slope -= dSlope` with `pt.slope = _maxAndSub(pt.slope, dSlope)`.
A scheduled slope change larger than the remaining aggregate slope can no longer
underflow → the weekly walk cannot revert-loop permanently. This is the direct
floor for the observed DoS.

**(b) `removeNominee` now reconciles the aggregate.** It captures the nominee's
still-active aggregate slope *before* zeroing it, zeroes **both** bias and slope,
subtracts the slope from the total, and cancels the nominee's future scheduled
slope changes:

```solidity
uint256 nomineeSlope = pointsWeight[nomineeHash][nextTime].slope;   // authoritative, see below
pointsWeight[nomineeHash][nextTime].bias  = 0;
pointsWeight[nomineeHash][nextTime].slope = 0;
...
pointsSum[nextTime].bias  = _maxAndSub(oldSum, oldWeight);
pointsSum[nextTime].slope = _maxAndSub(pointsSum[nextTime].slope, nomineeSlope);
...
uint256 t = nextTime;
for (uint256 i = 0; i < MAX_NUM_WEEKS; ++i) {
    t += WEEK;
    uint256 dSlope = changesWeight[nomineeHash][t];
    if (dSlope > 0) {
        changesSum[t] = _maxAndSub(changesSum[t], dSlope);
        changesWeight[nomineeHash][t] = 0;
    }
}
```

Three facts make this exact and complete, each checked firsthand:

- **The slope read is authoritative.** `nomineeSlope` is read from
  `pointsWeight[nomineeHash][nextTime].slope` — the *same slot*, under the *same*
  `nextTime = (block.timestamp + WEEK) / WEEK * WEEK` convention, that the voting path
  (`voteForNomineeWeights`, `:543–549`) maintains. `_getWeight` (called two lines
  above) advances the nominee checkpoint through `nextTime` and writes that slot, so
  the read is the freshly-checkpointed aggregate slope of the nominee. Subtracting it
  from `pointsSum[nextTime].slope` is therefore the exact mirror of how a vote adds it.
- **The `changesSum` strip is precise and non-interfering.** `changesWeight[N][t]` is,
  by construction, exactly N's contribution to `changesSum[t]`; subtracting it removes
  only N's phantom decrement and leaves other nominees that share week `t` untouched.
- **The horizon covers the maximum lock.** `MAX_NUM_WEEKS = 250` (`:156`),
  `WEEK = 604_800` (`:147`). The maximum veOLAS lock is 4 years ≈ **209 weeks**, so the
  loop reaches every future week that could carry a scheduled `changesWeight[N][t]`.
  No far-future decrement is missed.

**(c) `revoke` reduced to pure per-user cleanup (also closes F-5 / #20).** Since
`removeNominee` now fully reconciles the aggregate, `revokeRemovedNomineeVotingPower`
must no longer touch `pointsSum` / `pointsWeight` / `changesSum` / `changesWeight` —
doing so would double-subtract the nominee's slope. Both former aggregate blocks were
removed; the function now only releases the caller's own bookkeeping:

```solidity
uint256 powerUsed = voteUserPower[msg.sender] - oldSlope.power;
voteUserPower[msg.sender] = powerUsed;
delete voteUserSlopes[msg.sender][nomineeHash];
```

This is a genuine design improvement over `internal20`'s suggested F-5 remediation
(which was "advance the checkpoint first, mirroring `voteForNomineeWeights`"): by
moving *all* aggregate accounting into `removeNominee`, the aggregate is now correct
**regardless of whether any user ever revokes** — which was the fatal dependency of
the original design (the checkpoint could be bricked before voters got a chance to
clean up).

### 2.2 Adversarial checks (no residual finding)

- **Re-add / stale-state:** removal is terminal. `_addNominee` reverts `NomineeRemoved`
  while `mapRemovedNominees[hash] > 0` (`:304`), and that map entry is set on removal
  (`:652`) and never cleared; `voteForNomineeWeights` also reverts on removed nominees
  (`:487`). A removed nominee can never be re-activated, so leftover per-user
  `voteUserSlopes` entries cannot be chained back into the aggregate.
- **Expired voter:** a voter whose lock ended before removal already decayed out of
  `pointsWeight[N][nextTime].slope` and had its `changesWeight[N][end]` consumed during
  the walk, so `removeNominee` neither over- nor under-counts it, and the removed
  `revoke` block (guarded by `oldSlope.end > block.timestamp`) would not have fired
  anyway. Covered by `test_RemoveNominee_ExpiredVoter_NoUnderflow`.
- **`_nomineeRelativeWeight` cap (F-3 / #18):** the `1e18` clamp defends the off-repo
  `Dispenser` consumer against any residual drift; it changes nothing on a
  correctly-accounted aggregate and only bounds the pathological case.

## 3. Test verification (firsthand)

- **`forge test --mc VoteWeighting` on the fix branch → 17 / 17 unit tests PASS**
  (`ForkVoteWeighting` skipped — no fork RPC configured in this environment).
- **Rule: the regression must fail on the pre-fix parent.** Reverting *only*
  `contracts/VoteWeighting.sol` to base `a7f6189` while keeping the new tests, the
  three core regressions **fail** with root-invariant assertions:

  | Test | Failure on parent |
  |---|---|
  | `test_RemoveWithoutUnvote_NoCheckpointDoS` | `sum must equal the single surviving nominee weight` |
  | `test_RemoveNominee_ReconcilesSlopeAndChangesSum` | `sum slope must drop by removed nominee slope` |
  | `test_RemoveNominee_MultiVoter_FullReconcile` | `both voter slopes removed` |

  The tests assert the **accounting invariant directly** (sum equals the surviving
  nominee weight; the aggregate slope drops by exactly the removed nominee's slope)
  rather than merely awaiting the eventual underflow revert — a stronger, deterministic
  form that pins the drift at its root. This confirms the tests genuinely bind the bug.

## 4. Notes (non-blocking)

- **Gas of the strip loop.** The `MAX_NUM_WEEKS = 250` loop in `removeNominee` costs on
  the order of a few million gas worst-case, but `removeNominee` is owner-gated
  (governance → Timelock), so there is no griefing surface and the cost stays within the
  block limit. Acceptable.
- **`_maxAndSub` is defensive here.** On this fresh non-upgradeable redeploy there is no
  pre-existing drift, so the saturating guards are belt-and-suspenders — the correct,
  conservative choice (make the unsafe state unrepresentable).
- **Top-level `audits/README.md` not mirrored.** Per repo convention `audits/README.md`
  copies the *latest full audit*; this targeted fix-verification intentionally leaves the
  comprehensive `internal20` copy in place. Deferred to the maintainer whether to mirror.

## 5. Subsequent changes on the branch (post-verification)

After this verification (`a22490e`) the PR branch advanced to `8326d36`. The commits
added since, and their bearing on this verification:

| Commit | Change | Bearing on this verification |
|---|---|---|
| `83f6d3e` | Drop audit finding-number tags from `VoteWeighting` / harness comments | Cosmetic (comments only) — no effect |
| `998418b` | **Make `dispenser` immutable, drop `changeDispenser()` + `DispenserUpdated`; constructor becomes `(address _ve, address _dispenser)`** | **Functional / out of scope** — see below |
| `64026be` | Comments; pragma bump `^0.8.25 → ^0.8.30` | Comments + compiler-target change — no logic change |
| `367004d` | Add Forge deploy script `deploy_23_vote_weighting.sh` | New deploy tooling — out of scope |
| `8326d36` | Variable-declaration reorder (group the `dispenser` immutable with `ve`) | Cosmetic (declaration order of immutables) — no storage-layout or logic change |

**The `removeNominee` / revoke accounting verified above is unchanged by all of these.**
Diffing `a22490e..8326d36` on `VoteWeighting.sol`, the only non-comment code deltas are
the constructor signature, the `dispenser` immutability, and the removal of
`changeDispenser` / `DispenserUpdated` — `_getSum`, `_getWeight`, `removeNominee`
reconciliation, `revokeRemovedNomineeVotingPower`, the `_maxAndSub` guards and the
`1e18` clamp are byte-for-byte identical (only shifted ~7 lines down).

**Not covered by this verification (needs separate review):** the immutable-`dispenser`
refactor (`998418b`). It is a constructor-signature/ABI change with a deployment-ordering
consequence — the Dispenser must be deployed before `VoteWeighting`, and a future
Dispenser migration forces a `VoteWeighting` redeploy. Its safety rests on the tokenomics
`Dispenser` independently authorizing `addNominee` / `removeNominee` by
`msg.sender == voteWeighting` (with `addNominee` additionally pause-gated), which is a
cross-repo property outside this document's scope.

## 6. Verdict

**PASS — merge-ready for the accounting fix (`a22490e`).** PR #215 closes `internal20`
F-3, F-4, F-5, F-6, F-9 (vuln-list #8, #11, #18, #19, #20) at the source, the
reconciliation is exact and complete, the DoS regression fails on the pre-fix parent and
passes on the fix, and no new defect was found in the changed accounting code — which is
unchanged at the current branch tip `8326d36`.

**Scope caveat:** this verdict covers the accounting fix only. The immutable-`dispenser`
refactor (`998418b`) that the branch has since gained is a separate functional change and
is **not** part of this PASS — see §5.
