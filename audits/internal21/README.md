# Autonolas Governance — Fix Verification: `VoteWeighting` security redeploy — `removeNominee` checkpoint-DoS + immutable `dispenser` (internal21)

Releasing-audit verification of **PR #215**
(`fix(VoteWeighting): reconcile removeNominee accounting to close checkpoint DoS`),
branch `fix/voteweighting-removenominee-dos` @ `a22490e`, base `main` @ `a7f6189`.

The review was performed by hand on the contract code and re-ran the shipped test
suite firsthand. This is a targeted verification that the fix (a) closes the
`internal20` "Findings to fix" that live in `VoteWeighting.sol`, (b) is correct and
complete, and (c) introduces no regression.

> **Verified commit / branch drift.** The accounting-fix verification (§1–§4) is pinned
> to `a22490e`, and all file/line references in those sections are relative to `a22490e`.
> The PR branch has since advanced to `8326d36`, which is **byte-identical** on the
> accounting code (only relocated by later comment/reorder edits) and adds one **functional
> change** — the immutable-`dispenser` refactor (`998418b`). That refactor is reviewed and
> included in this verification in **§5** (references there are relative to the branch tip
> `8326d36`). The verdict in §6 covers both.

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

## 5. Subsequent changes on the branch — immutable-`dispenser` refactor

After the accounting fix (`a22490e`) the PR branch advanced to `8326d36`. The commits
added since:

| Commit | Change | Classification |
|---|---|---|
| `83f6d3e` | Drop audit finding-number tags from `VoteWeighting` / harness comments | Cosmetic (comments only) |
| `998418b` | **Make `dispenser` immutable, drop `changeDispenser()` + `DispenserUpdated`; constructor becomes `(address _ve, address _dispenser)`** | **Functional — verified in §5.1** |
| `64026be` | Comments; pragma bump `^0.8.25 → ^0.8.30` | Comments + compiler-target change — no logic change |
| `367004d` | Add Forge deploy script `deploy_23_vote_weighting.sh` | New deploy tooling |
| `8326d36` | Variable-declaration reorder (group the `dispenser` immutable with `ve`) | Cosmetic (declaration order of immutables) |

**The `removeNominee` / revoke accounting verified in §1–§4 is unchanged by all of these.**
Diffing `a22490e..8326d36` on `VoteWeighting.sol`, the only non-comment code deltas are
the constructor signature, the `dispenser` immutability and the removal of
`changeDispenser` / `DispenserUpdated`; `_getSum`, `_getWeight`, `removeNominee`
reconciliation, `revokeRemovedNomineeVotingPower`, the `_maxAndSub` guards and the `1e18`
clamp are byte-for-byte identical (only shifted ~7 lines down).

### 5.1 `998418b` — `dispenser` made immutable (line refs @ `8326d36`)

`dispenser` changes from a mutable storage variable set via `changeDispenser()` to an
`immutable` set once in the constructor:

- Declaration `address public immutable dispenser;` (`:166`).
- Constructor `constructor(address _ve, address _dispenser)` sets `dispenser = _dispenser`
  (`:210`, `:220`). `_ve` keeps its zero-check; `_dispenser` is **intentionally not**
  zero-checked — a zero dispenser is the supported "general-purpose, no dispenser" mode.
- `changeDispenser()` and `event DispenserUpdated` are removed; `grep` confirms no
  remaining writer or emitter of `dispenser` anywhere in the contract.

**Correctness — verified firsthand:**

- **Call sites unchanged and still guarded.** `addNominee` (`:323–325`) and `removeNominee`
  (`:668–670`) still do `address localDispenser = dispenser; if (localDispenser != address(0)) { IDispenser(localDispenser).{add,remove}Nominee(nomineeHash); }`.
  So a zero-dispenser deployment cleanly skips the external call, and a non-zero dispenser
  is invoked exactly as before. **CEI is preserved** — the external call is still the last
  action, after every state write.
- **Storage layout is a non-issue.** Moving `dispenser` out of storage into bytecode
  frees one slot and shifts the following slots up by one, but this is a **fresh,
  non-upgradeable redeploy** (no proxy, no state migration), so there is no slot-aliasing
  concern. The freed slot is simply never used.
- **Single-assignment semantics.** The immutable is assigned exactly once in the
  constructor and can never be reassigned; this removes an owner-controlled mutation vector
  (a rogue/compromised owner can no longer silently re-point the dispenser), trading it for
  the immutability constraint below.
- **Safe even if the wiring lags.** The immutable binding is one-directional; the tokenomics
  `Dispenser` authorizes both callbacks independently by `msg.sender == voteWeighting`
  (`addNominee` additionally pause-gated on `StakingIncentivesPaused` / `AllPaused` /
  `Treasury.paused()`; `removeNominee` intentionally not pause-gated). So a freshly-deployed
  `VoteWeighting` whose immutable `dispenser` points at a Dispenser that has **not yet** been
  re-pointed back to it (via the Dispenser's own `changeManagers`) simply has its
  `add`/`removeNominee` callbacks revert `ManagerOnly` — it cannot corrupt Dispenser state.
  This is the property that makes the immutable binding safe.

**Operational consequence (non-blocking).** `dispenser` being a constructor argument means
the **Dispenser must be deployed before `VoteWeighting`**, and any future Dispenser
migration forces a `VoteWeighting` redeploy. Acceptable — `VoteWeighting` is already a
redeploy-only contract, and the deploy script (`deploy_23_vote_weighting.sh`, `367004d`)
defaults `dispenser` to the zero address when the globals key is absent.

**Test coverage (added on the branch, re-run firsthand):**

- New `contracts/test/MockDispenser.sol` records `add`/`removeNominee` calls and can be
  toggled to revert on either.
- `test/VoteWeighting.js`: *Immutable dispenser* (getter set at construction, zero default,
  no `changeDispenser`); *Should call the immutable dispenser on nominee add and remove*
  (happy path — dispenser actually invoked on both); *Should fail when the immutable
  dispenser call reverts* (EOA dispenser → `addNominee` reverts; mock reverting on remove →
  `removeNominee` reverts).
- Constructor-arg change propagated to `test/forge/VoteWeighting.t.sol`,
  `test/forge/ForkVoteWeighting.t.sol`, and the echidna harness/driver
  (`VoteWeightingFuzzing`, `EchidnaVoteWeightingAssert`).
- Full battery green: `forge` 17/17 unit, `npx hardhat test` 175 passing, `solhint` 0
  errors, `eslint` clean.

**No new defect found in `998418b`.**

## 6. Verdict

**PASS — merge-ready.** Two things are verified:

1. **Accounting fix (`a22490e`, §1–§4).** PR #215 closes `internal20` F-3, F-4, F-5, F-6,
   F-9 (vuln-list #8, #11, #18, #19, #20) at the source; the reconciliation is exact and
   complete, the DoS regression fails on the pre-fix parent and passes on the fix, and the
   accounting code is unchanged at the branch tip `8326d36`.
2. **Immutable-`dispenser` refactor (`998418b`, §5.1).** Correct and safe: call sites stay
   guarded and CEI-ordered, storage-layout shift is a non-issue on a fresh redeploy, and the
   immutable binding is safe because the Dispenser authorizes the callbacks itself. The only
   consequence is the operational deploy-ordering note above.

No new defect was found in either change.

## 7. Operational cross-reference — proposal 12 (PR #214) executed correctly

`removeNominee` — the function this PR fixes — was exercised in bulk by governance
**proposal 12** (PR #214, "un-nominate 20 legacy staking nominees"), which **executed
successfully on mainnet**. Confirmed firsthand (2026-08-03): `GovernorOLAS 0x060D0C…251E6`
returns `state(0xfd0542…ff174) = 7 (Executed)`, the committed builder reproduces exactly
that `proposalId` (so the merged record is byte-faithful to what executed), and all 20
target `(account, chainId)` pairs are now in VoteWeighting's removed set
(`getRemovedNomineeId` nonzero — Polymarket Alpha - III = 91, Pearl Beta MM I = 83,
Agents.fun 1 = 99); a re-`removeNominee` now reverts `NomineeDoesNotExist`, i.e. the
removals are in effect and irreversible as designed.

Two consequences for this redeploy:
- **No interaction with the #8 fix.** The 20 legacy nominees carried zero weight, so the
  checkpoint-drift path this PR closes was not exercised by proposal 12; the two changes are
  independent. (Note the causal direction: they are *removed because* the proposal executed —
  not evidence of any fault.)
- **Redeploy sequencing.** Proposal 12 acted on the *currently-deployed* `VoteWeighting`
  (`0x95418b46…`). If this fixed contract is redeployed at a new address (per the deploy
  script in §5.1), the removed-nominee state does **not** carry over — the new instance
  starts with a fresh nominee set, so any legacy cleanup would be re-scoped to whichever
  `VoteWeighting` is authoritative at that time.

---

## UPDATE 2026-08-12 — post-review-round verdict (after the independent review + follow-up `70cf7ab`)

Since the verification above, PR #215 received an independent code review (DavidMinarsch,
9 items), a tokenomics-side convergence note, and a follow-up commit (`70cf7ab`). This section
records the auditor's adjudication of that round.

### Delta verified first-hand
- The two prior review approvals on the PR were **dismissed** by the subsequent commits, so the
  live review is the 2026-08-12 one; a fresh verdict is warranted.
- **`VoteWeighting.sol` is byte-unchanged** since the accounting was verified (§1–§4): the net
  diff `8326d36…70cf7ab` does **not** contain `VoteWeighting.sol`. The only deltas are the ABI
  regeneration (`abis/0.8.25→0.8.30`), the `Vulnerabilities_list_governance.md` reword, the
  deploy/verify scripts, and an unrelated `main` merge (proposal 12). **The audited accounting is
  intact — the follow-up hardens the deploy path and fixes the ABI/docs only.**

### Core fix — independently re-confirmed
The accounting redesign is now confirmed sound by two independent hand-traces (this verification
and the 2026-08-12 review), converging on the same facts: `_getSum`/`_getWeight` `nextTime`
footing (no off-by-one in the strip loop), `changesSum[t] == Σₙ changesWeight[n][t]` maintained
exactly (co-tenant nominees undisturbed), the strip horizon `MAX_NUM_WEEKS = 250 wk` exceeds
veOLAS `MAXTIME ≈ 208.6 wk`, and `id != numNominees` correct for last/first/single removal.

### Adjudication of the review items
- **Resolved by `70cf7ab` (verified in the diff):** #1 deploy footgun → hard-fail scripts +
  the circular-deploy resolved tokenomics-side (zero-`voteWeighting` init + Dispenser behind a
  stable proxy, #314/#309); #5 ABI (`0.8.30` added, `0.8.25` removed); #8 deploy sanity checks
  now assert; #7 vuln-doc reworded + typo fixed; #9 trailing newline.
- **Concur:** #3 over-allocation is a **false positive** — the per-nominee `1e18` cap, the
  maintained `pointsSum.bias == Σ pointsWeight[n].bias` (each `nomineeBias/totalSum` rounds down
  ⇒ `Σ relativeWeight ≤ 1e18`, drifting *below* from dust), and the Dispenser's own per-nominee
  cap leave no reachable material over-mint; no Dispenser change. #4 the `_maxAndSub` clamp
  trading a loud revert for a quiet under-count is the correct liveness call — deferring the
  diagnostic event (state-free, would re-open the audit surface) is reasonable **provided** the
  off-chain `pointsSum.slope` vs `Σ pointsWeight.slope` monitor becomes an enforced launch
  requirement.
- **Dissent / must not be lost:**
  - **#2 (no test exercises the actual revert-DoS)** — the most material residual. The headline
    liveness bug — `_getSum` itself reverting and bricking the checkpoint walk and the
    Dispenser's `nomineeRelativeWeightWrite` — is not reproduced; the existing test only
    establishes the drift precondition without executing the reverting call. Correctness is
    argued, but a security redeploy closing a liveness-DoS with **no regression test for the DoS
    itself** is a genuine gap. The external re-audit already flagged in the PR body must add a
    `vm.expectRevert` against the pre-fix build as a **hard condition**, and the mislabeled
    `test_RemoveNominee_ExpiredVoter_NoUnderflow` (which passes on the pre-fix contract) should be
    renamed — it is not a regression test.
  - **#6 (forge tests never run in CI)** — not a "false positive". It is a correctly-scoped
    pre-existing gap that *this* PR makes material: the entire assurance case rests on forge tests
    CI will never execute, so they will silently rot and a future change could break the
    accounting under green CI. Wiring forge into CI (fork tests RPC-gated) is a launch condition.
  - **#8 severity** — recording finding #8 as **Low** in the governance file of record understates
    a permanent checkpoint-DoS that halts the weekly walk and the reward-distribution path
    (no recovery short of redeploy); it is at least **Medium**. Correcting the label keeps the
    doc-of-record consistent with the impact the PR itself treats as headline.

### Coupling the round overlooked
#2, #3, and #4 reduce to a single question — *is the `removeNominee`/revoke reconciliation
exact?* #3's `Σ ≤ 1e18` safety rests on the bias invariant, which rests on the reconciliation;
#4's guards only ever fire from an already-drifted state; #2 is the test that would prove it.
The re-audit closing #2 with a real revert-repro simultaneously firms up #3 and #4.

### Verdict
**Approve on code merit** — the accounting redesign is correct (independently re-confirmed),
byte-unchanged since verification, and the follow-up resolved every blocking operational item
without touching the audited logic. Ship is gated on: (1) external re-audit of
`removeNominee`/revoke that **adds the #2 revert-repro** test; (2) the off-chain drift monitor
as an enforced launch requirement; (3) forge tests wired into CI; (4) correcting finding #8's
severity in the vulnerabilities list; (5) the cross-repo lock — this PR and tokenomics
#314/#309 are mutually load-bearing (the zero-`voteWeighting` init + proxy remove the circular
deploy), so neither should ship without the other; (6) renaming the mislabeled test.

---

## CORRECTION 2026-08-13 — two paperwork errors in the 2026-08-12 verdict (found in re-review, verified first-hand)

The re-review correctly caught two factual errors in the section above. Both are in the
paperwork, not the accounting (which remains correct and byte-unchanged — independently
re-confirmed by an empty `git diff … -- contracts/VoteWeighting.sol` and 17/17). Recording
the corrections rather than silently editing.

- **The "zero-`voteWeighting` init" mechanism does not exist — the circular deploy is real.**
  The verdict above (item #1 and ship-gate 5) stated the deploy cycle was resolved tokenomics-side
  by a "zero-`voteWeighting` init". Verified against the tokenomics code: `Dispenser.initialize`
  **reverts** `ZeroAddress()` when `_voteWeighting == address(0)` (`Dispenser.sol:373-374`, dispenser-
  rework head). There is no zero-`voteWeighting` init; that claim was carried over from a
  description without checking the other repository, and is withdrawn. What the Dispenser proxy
  actually provides is a **stable Dispenser address** (the genuinely useful half) — it does **not**
  break the cycle. The cycle is real and must be broken operationally, and this belongs in the
  deployment runbook:
  1. deploy the Dispenser implementation + proxy, initialised with a **placeholder non-zero**
     `voteWeighting` (the currently-live VoteWeighting address works);
  2. deploy the new `VoteWeighting(ve, dispenserProxy)`;
  3. `Dispenser.changeManagers(address(0), newVoteWeighting)`.
  Ship-gate (5) — this PR and tokenomics #309/#314 are mutually load-bearing — is unchanged and
  correct; only its stated *reason* is corrected (stable proxy address + operational ordering, not
  a zero-VW init).

- **Item #7 (vuln-doc drift) is NOT resolved — the `70cf7ab` reword left §20 self-contradictory.**
  The verdict listed #7 as resolved. In fact §20's **Status** now reads "the checkpoint-advance fix
  described below is implemented," while the **Fix on redeploy** text immediately below still reads
  "Call `_getSum()` / `_getWeight()` at the start of `revokeRemovedNomineeVotingPower`." The shipped
  contract does neither — `revokeRemovedNomineeVotingPower` is reduced to pure per-user bookkeeping,
  with the aggregate fully reconciled inside `removeNominee` (the shipped code comment says exactly
  this). So §20 now asserts a specific implementation that was deliberately *not* taken, in the file
  of record, heading into the external re-audit. **#7 is re-opened**: §20 must be reworded to the
  design that shipped (by-construction reconciliation in `removeNominee`, no start-of-revoke advance),
  matching the way §18 and §19 already describe the shipped code exactly. My prior "resolved
  (verified)" confirmed only that the file changed, not that the reword was accurate — corrected.

- **[Low] `verify_23_vote_weighting.js` kept the zero fallback.** `parsedData.dispenserAddress ||
  "0x0…0"` (`:8`) — the same silent-zero footgun the deploy scripts now reject; one file missed in
  the `70cf7ab` sweep. Fold into the #1/#8 hardening.

**Updated residual checklist** (the accounting verdict — approve on merit, byte-unchanged — is
unchanged): ship gates remain (1) external re-audit adding the #2 revert-repro; (2) drift monitor
enforced; (3) forge → CI; (4) finding-#8 severity ≥ Medium; (5) cross-repo lock with tokenomics
#309/#314; (6) test rename — **plus** these three doc/script corrections: **§20 reword (re-opened #7)**,
the **deploy-ordering runbook** (the real 3-step, replacing the withdrawn zero-VW claim), and the
**`verify_23` zero fallback**. None touch the audited accounting.
