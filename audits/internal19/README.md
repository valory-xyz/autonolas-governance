# Autonolas Governance — Internal Security Re-Audit (internal19)

The review was performed on the contract code in this repository on the `main` branch
(commit `bae8da6`).

This is a comprehensive, from-scratch re-audit of the in-scope `autonolas-governance` contract set,
independent of prior internal reviews. The goal was a thorough adversarial assessment of every
in-scope production contract, with particular attention to the historical-view (vote-escrow) surfaces,
the gauge-weighting accounting, the Community-Multisig guard stack, and the cross-chain governance
execution path.

**Overall verdict: PASS-WITH-FINDINGS — 0 Critical / 0 High / 0 Medium / 6 Low / 15 Info.**

No defect was found by which an unprivileged actor can subvert the live governance system, mint or
move funds, or cause an unauthorized cross-chain execution. The confirmed findings are correctness,
robustness, and governance-design issues: a cluster of raw vote-escrow view surfaces that are correct
only when consumed through the deployed wrapper, an owner-gated accounting fragility in the
gauge-weighting contract, hardening gaps in the cross-chain message parsers, and several
self-inflicted-liveness and trust-boundary notes. The recurring theme is
*safety-by-wrapper / safety-by-operator-discipline*: several primitives are correct only because the
deployment routes around their raw surfaces or because a privileged operator follows an undocumented
sequence. We recommend hardening the primitives themselves so correctness does not depend on every
future integrator and operator behaving exactly as the current deployment does.

---

## Scope

The **26 in-scope production contracts** (interfaces excluded). The deprecated `buOLAS` token is
**excluded from scope** — it is marked *deprecated* in the repository `README.md` and is not part of
the active governance surface, so it is not re-audited here.

| Group | Contracts |
|---|---|
| Token / escrow | `OLAS.sol`, `veOLAS.sol`, `wveOLAS.sol` |
| Gauge weighting | `VoteWeighting.sol` |
| Governor / timelock | `GovernorOLAS.sol`, `Timelock.sol`, `utils/GovernorTimelockControl.sol` |
| Multisig guard | `multisigs/GuardCM.sol`, `multisigs/VerifyData.sol`, `multisigs/bridge_verifier/VerifyBridgedData.sol`, `multisigs/bridge_verifier/ProcessBridgedData{Arbitrum,Gnosis,Optimism,Polygon,Wormhole}.sol` |
| Cross-chain relays | `bridges/{FxGovernorTunnel,HomeMediator,OptimismMessenger,WormholeMessenger,WormholeRelayerTimelock,BridgeMessenger,FxERC20ChildTunnel,FxERC20RootTunnel,BridgedERC20}.sol` |
| Misc | `Burner.sol`, `DeploymentFactory.sol` |

All in-scope contracts compile under Solidity `^0.8.15`–`^0.8.30` (checked arithmetic throughout; the
only `unchecked` blocks among the in-scope contracts are in `veOLAS`, examined explicitly).

---

## 1. Findings by severity

### CRITICAL — none
### HIGH — none
### MEDIUM — none

---

### LOW

#### L-1 — `veOLAS.getPastVotes` fabricates non-zero voting power for blocks before an account's first lock (missing pre-first-checkpoint guard)

- **Location:** `veOLAS.sol:672-684` (`getPastVotes`); contrast the guard at `balanceOfAt` (`veOLAS.sol:626`), the same guard at `totalSupplyAt` (`veOLAS.sol:730`), and the wrapper re-adding it at `wveOLAS.sol:211-218`.
- **Mechanism:** `getPastVotes(account, blockNumber)` calls `_findPointByBlock`. For an account that has locked but only *after* the queried block, the binary search drives to `minPointNumber == 0` and returns `mapUserPoints[account][0]` — the lock-creation point, whose `blockNumber` is strictly *greater* than the requested block — with no check that `point[0].blockNumber <= blockNumber`. Line 680 then computes `uPoint.bias -= uPoint.slope * (blockTime - uPoint.ts)`; because `_getBlockTime` interpolates a `blockTime` earlier than the lock-creation `ts`, the term is **negative**, so the subtraction *increases* the bias to `slope * (endTime - blockTime) > 0`. The function returns fabricated positive voting power at a snapshot where the account held nothing. The never-locked case is clean (early-return of a zero struct at `551-553`); the defect is specifically the *locked-after-snapshot* case. `balanceOfAt` and `totalSupplyAt` carry the guard; `getPastVotes` does not, and the wrapper re-adds exactly this guard — dispositive evidence the raw function is knowingly unsafe.
- **Impact / reachability:** Not reachable against the deployed protocol: the live `GovernorOLAS`/`GovernorTwo` is constructed against the `wveOLAS` wrapper, whose `getPastVotes` short-circuits to 0 for any pre-first-point query, and no in-repo contract reads the raw token's historical views. Exposure is confined to a third-party integrator that wires an `IVotes` consumer to the raw `veOLAS` address instead of the wrapper — i.e. the token's own `IVotes` implementation is non-self-safe.
- **Fix:** Port the guard into `getPastVotes`: after `_findPointByBlock`, if `uPoint.blockNumber == 0 || blockNumber < uPoint.blockNumber`, return 0.
- **Severity rationale:** Deployed governance is deterministically protected by the wrapper; above Info because the token's own `IVotes` surface is genuinely non-self-safe for any direct consumer.

#### L-2 — `VoteWeighting.removeNominee` leaves a dangling slope: weighting skew, uncapped `relativeWeight > 1e18`, and an owner-scoped liveness revert

- **Location:** `VoteWeighting.sol:603-613` (`removeNominee` adjusts only `bias`, never `slope`/`changesSum`); `:611` (unclamped `newSum = oldSum - oldWeight`); `:420-435` (`_nomineeRelativeWeight`, no cap); helper `_maxAndSub` at `:579-581`.
- **Mechanism:** On removal, `pointsSum[nextTime].bias` is reduced by `oldWeight`, but `pointsSum[nextTime].slope` is **not** reduced and the removed nominee's scheduled `changesSum` decrements are **not** cancelled. Reconciliation is deferred to per-voter `revokeRemovedNomineeVotingPower`, which only some voters may ever call. Until then `_getSum` keeps subtracting the removed nominee's slope, so the global sum over-decays relative to surviving nominees. Two consequences flow from this one root cause: (1) **Uncapped relative weight** — `_nomineeRelativeWeight` computes `1e18 * nomineeWeight / totalSum` with **no clamp to `1e18`**, despite the docstring promising "not more than 1.0"; with an under-counted denominator the value can exceed `1e18`. (2) **Owner-scoped liveness revert** — line 611 is the *lone raw subtraction* in the accounting path (every peer delta uses `_maxAndSub`); once `totalSum` over-decays below a surviving nominee's weight, a subsequent `removeNominee` of that survivor computes `oldSum - oldWeight` and **reverts** (checked underflow), bricking `removeNominee` until the sum re-syncs.
- **Impact:** Trigger is owner-only; `VoteWeighting` holds no funds and performs no transfers. In-contract effect is a skewed view value and a self-healing liveness window for a privileged caller. The only funds-impact (over-allocation) would live in an out-of-scope incentive distributor that assumes `Σ relativeWeight == 1e18`.
- **Fix:** (1) Cap the view: `if (weight > 1e18) weight = 1e18;`. (2) Use `_maxAndSub` on line 611. (3) Best: subtract the removed nominee's slope from `pointsSum[nextTime].slope` and cancel its pending `changesSum` events in `removeNominee` itself.

#### L-3 — `veOLAS._checkpoint` history-fill loop hard-capped at 255 weeks; a >~4.9-year global-checkpoint gap corrupts vote-weight accounting (withdrawals stay safe)

- **Location:** `veOLAS.sol:232-272` (the `for (i = 0; i < 255; ++i)` week loop), mirrored in `_supplyLockedAt` (`693-710`).
- **Mechanism:** The loop walks weekly slope-change buckets toward `block.timestamp`, advancing `tStep += WEEK` per iteration (~4.88 years total). If no `_checkpoint` is triggered for >255 weeks, the loop exhausts before reaching now: the global supply point's `ts` never advances and intermediate slope changes beyond the window are skipped, corrupting `getPastTotalSupply`/`totalSupplyLocked`. The author's own comment (`233-234`) self-describes this. Standard Curve ve design (`MAXTIME ~208 weeks < 255`).
- **Impact:** Requires the **global** checkpoint to go un-poked for ~4.88 continuous years. `checkpoint()` is permissionless and every state-touching interaction (`createLock`/`depositFor`/`increaseAmount`/`increaseUnlockTime`/`withdraw`) resets the clock, so it bites only a fully dormant contract; no attacker can prevent others from poking it. Consequence is corrupted *global* accounting, **not** fund loss — `withdraw` reads only per-account state.
- **Fix:** None required for funds. Document the 255-week liveness assumption or run a periodic `checkpoint()` keeper. Acceptable as a known Curve-port limitation.

#### L-4 — `VoteWeighting.removeNominee` last-element guard mismatches intent — removing the last of ≥2 nominees leaves a dangling non-zero `mapNomineeIds`

- **Location:** `VoteWeighting.sol:622-633` (guard at `:625`; intent comment at `:623`).
- **Mechanism:** The swap-and-pop is gated by `if (numNominees > 1)`, but the intent (per the comment) is "shuffle only if it's not the last nominee." `numNominees > 1` ≠ "removed id is not the last index." When removing the **last** of ≥2 nominees, the branch still fires: it re-reads the nominee being removed, recomputes its hash, and sets `mapNomineeIds[removedHash] = id`, **re-writing the value that line 620 had correctly zeroed**, then pops. Post-state: the removed nominee is present in **both** `mapRemovedNominees` and `mapNomineeIds` (dangling past array end). The correct guard is `id != numNominees`. (The non-last path shuffles correctly, so no surviving nominee's id is ever corrupted.)
- **Impact:** `getNomineeId`/`getNextAllowedVotingTimes` (which key existence off `mapNomineeIds == 0`) return stale liveness/timing hints to off-chain indexers. All **on-chain** value-bearing paths are independently guarded by `mapRemovedNominees` (re-add blocked, `voteForNomineeWeights` blocked, `getNominee(staleId)` reverts on the length bound) — the dangling entry cannot be chained into fund/vote impact.
- **Fix:** Replace `if (numNominees > 1)` with `if (id != numNominees)`.

#### L-5 — Cross-chain verifiers do not bound the per-record native `value`; the L2 executor spends it (value-spend uncovered by the Guard allowlist — systemic across all five verifiers)

- **Location:** `multisigs/bridge_verifier/VerifyBridgedData.sol:44-51` (the parse skips the 12-byte `value`: `i := add(i, 16)` jumps over value+payloadLength, value never read) and `_verifyData` (`:72`) authorizes only `(target, selector, chainId)`; the executors spend it — `bridges/HomeMediator.sol:160`, `bridges/FxGovernorTunnel.sol:160`, `bridges/BridgeMessenger.sol:73` — all `target.call{value: value}(payload)`, bounded only by `value <= address(this).balance`.
- **Mechanism:** A Guard-authorized `(target, selector, chainId)` triple says nothing about the native `value` the L2 mediator will forward. A scheduled bridged blob can attach an arbitrary `value` (up to the mediator's balance) to a call whose `(target, selector)` is allowlisted; the verifier never sees it. The Guard's implicit threat model — "the CM can only invoke allowlisted selectors and moves no value" — holds for the selector half but not the value half.
- **Impact:** Trigger is the Community Multisig (already a guarded, threshold-trusted entity); the destination is an **allowlisted** target only; the amount is bounded by whatever native balance the mediator happens to hold (typically ~0 for a pure relay). No unprivileged path, no arbitrary-recipient theft. A genuine but bounded gap.
- **Fix:** Read the 12-byte `value` in `_verifyBridgedData` and enforce `value == 0` for non-payable allowlisted selectors (mirroring `ProcessBridgedDataArbitrum`'s `l2CallValue` handling), or bound it per target.

#### L-6 — `GuardCM` can be self-released by the Community Multisig via a terminally-`Defeated` heartbeat proposal (the contained party can shed its own containment)

- **Location:** `GuardCM.sol` pause/heartbeat path (`pause` reads `IGovernor(governor).state(governorCheckProposalId)`); `governorCheckProposalId` default set at construction, changeable only by the owner (Timelock).
- **Mechanism:** The Guard auto-releases (allows the CM to operate unguarded) when its heartbeat proposal reaches a terminal `Defeated` state — a liveness backstop intended to prevent the Guard from permanently freezing the DAO if governance dies. But the CM influences whether the referenced proposal ever reaches quorum, so the contained party has a hand in driving the release condition.
- **Impact:** The CM is a threshold multisig and a trusted operational backstop, and re-pointing the heartbeat is owner(Timelock)-gated; this is a deliberate liveness/safety trade-off, not an unprivileged bypass. It is surfaced as Low (rather than Info) because it lets the *contained* party participate in releasing its own containment, which the DAO should consciously own — especially in combination with the CM's direct timelock roles (see the architecture note in §3).
- **Fix:** None strictly required if intended. Consider decoupling the release condition from any proposal the CM can influence, and document the trust assumption.

> **Severity note on the cross-chain message parsers.** Both the verifier (`VerifyBridgedData`) and every executor (`HomeMediator`/`FxGovernorTunnel`/`BridgeMessenger`) read the per-record 36-byte header with raw `mload` and only bound `data.length` once before the loop, so a malformed short tail causes an out-of-array `mload` of adjacent memory. We traced this to a **fail-closed** outcome in every case: the subsequent payload copy uses Solidity-bounds-checked `data[i + j]` (reverts on OOB), and a garbage `target` decodes from zeroed scratch memory to `address(0)` (reverts `ZeroAddress`). No unauthorized call escapes. We therefore rate the missing per-record bounds checks **Info** (I-11), with a recommendation to add explicit `dataLength - i >= 36` and `i + payloadLength <= dataLength` assertions for fail-fast clarity rather than relying on downstream reverts.

---

### INFO

- **I-1 — `revokeRemovedNomineeVotingPower` mutates `pointsSum`/`pointsWeight` slope without first checkpointing to `nextTime`** (`VoteWeighting.sol:663-668`). Unlike `voteForNomineeWeights`, it writes directly via `_maxAndSub` without advancing the checkpoint; on a stale slot the subtraction floors to 0 and the slope removal is silently lost, leaving a residual slope that over-decays the sum until natural expiry. Same skew class as L-2; no funds, self-converging. *Fix:* call `_getSum()`/`_getWeight(...)` at the start.
- **I-2 — `OwnerOnly` revert arguments swapped in `removeNominee`** (`VoteWeighting.sol:589-591`). The authorization check is correct; only the custom-error payload transposes `(owner, msg.sender)`. Cosmetic (selector unchanged). *Fix:* `revert OwnerOnly(msg.sender, owner);`.
- **I-3 — `OLAS` inflation cap bounds circulating `totalSupply`, not cumulative emission — burns recharge mint headroom** (`OLAS.sol:91-120`). `inflationRemainder = supplyCap - totalSupply`, and `burn` decrements `totalSupply`, so a `burn → mint` cycle lets lifetime emission exceed the nominal cap while instantaneous supply stays under it. Consistent with the contract's own "Total supply cap" naming; minter is governance. *Fix (optional):* track cumulative minted separately or document that the cap is a circulating-supply ceiling.
- **I-4 — `OLAS.mint()` silently no-ops (no revert, no boolean) when the amount exceeds inflation remainder** (`OLAS.sol:75-85`). Documented behaviour; an on-chain caller assuming success without re-checking balances could mis-account. Privileged minter; integration responsibility. *Fix (optional):* revert on cap-exceeded or return a checkable boolean.
- **I-5 — Unbounded compounding loop in `inflationRemainder`** (`OLAS.sol:105-111`). Recomputes the post-year-10 cap by looping `(numYears - 9)` times on every call; iteration count grows one per year. Negligible for centuries; no realistic DoS. *Fix (optional):* cache or derive closed-form.
- **I-6 — `GuardCM` authorizes scheduled timelock operations at `(target, selector, chainId)` granularity only — inner ETH value and call arguments are unconstrained (by design)** (`GuardCM.sol:203, 207-208`; `VerifyData.sol:23-37`). Once a tuple is allowlisted, the CM may schedule it with arbitrary arguments and value. Intentional; the allowlist is governance-curated. *Fix:* document that allowlisting a selector grants unbounded value/args; curate accordingly. (Closely related to L-5.)
- **I-7 — `GuardCM` delegatecalls into an owner-set verifier, which therefore has full write access to `GuardCM` storage** (`GuardCM.sol:221`; verifier set in `setBridgeMediatorL1BridgeParams`, owner-only, `code.length>0` checked). We confirmed every in-repo `ProcessBridgedData*` is strictly stateless (**0 `SSTORE`**, no external calls) and storage-layout-compatible with `VerifyData`, so the delegatecall cannot corrupt `GuardCM` state. Trust rests on the owner (Timelock/DAO) supplying a benign verifier — a privileged configuration responsibility, not a contract defect. *Fix:* document the delegatecall trust assumption.
- **I-8 — `setTargetSelectorChainIds` does not range-bound `chainId`** (`GuardCM.sol:330, 340`) while `setBridgeMediatorL1BridgeParams` bounds it to `MAX_CHAIN_ID`. The `<< 192` packing truncates **symmetrically** at write (`:340`) and enforcement read (`VerifyData.sol:31`), so high bits map to one consistent key — no field bleed, no authorization confusion. *Fix (optional):* bound `chainId <= MAX_CHAIN_ID` for consistency.
- **I-9 — `VerifyData._verifyData` relies on caller-supplied `data` length; short/empty data is handled safely** (`VerifyData.sol:23, 28`). `bytes4(data)` right-pads, but the only writer (`setTargetSelectorChainIds`) reverts on a zero selector, so an empty-calldata call always reverts `NotAuthorized`. Clean; the zero-selector ban is the load-bearing invariant.
- **I-10 — Empty `l2Message` is a vacuous pass in `_verifyBridgedData` (loop never runs) while the L2 executor reverts on it** (`VerifyBridgedData.sol:40-73`). Safe directional divergence: an empty bridged message carries zero records, nothing is authorized, and the executor reverts the relayed message. *Fix:* optionally revert early on empty data for symmetry.
- **I-11 — Cross-chain message parsers use unbounded header `mload` with only a single pre-loop length check** (`VerifyBridgedData.sol:44-51`; `HomeMediator.sol:130-140`; `FxGovernorTunnel.sol:130-140`; `BridgeMessenger.sol`). Fails closed in every case (see the §1 severity note). *Fix:* add explicit per-record `dataLength - i >= 36` and `i + payloadLength <= dataLength` assertions for fail-fast clarity.
- **I-12 — Arbitrum verifier: allowing `unsafeCreateRetryableTicket` is sound only because `l2CallValue == 0` and both refund addresses are forced to the aliased Timelock** (`ProcessBridgedDataArbitrum.sol:31,33,50-52,70-80`). The economic invariant holds (the only ETH spendable is the fully-refundable L1 inbox fee — the retryable-ticket creation cost plus gas), but the soundness is load-bearing on those equalities. *Fix:* add a comment/test pinning `l2CallValue == 0` + refund-equality against future refactors. (Also: refund correctness depends on the owner setting `bridgeMediatorL2` to the correctly address-aliased Timelock — disclaimed owner responsibility.)
- **I-13 — `wveOLAS` constructor does not cross-check `token == veOLAS.token()`** (`wveOLAS.sol:145-152`). `token` is an informational immutable consumed by no on-chain logic; a wrong value yields only a misleading getter. *Fix:* `require(_token == IVEOLAS(_ve).token())`.
- **I-14 — `wveOLAS` total-supply views are unguarded pass-throughs while user-point views are guarded — the asymmetry is correct, not a defect** (`wveOLAS.sol:256-287`). `veOLAS` self-guards the supply path (supply point 0 created in its constructor; `_getBlockTime` reverts on out-of-range supply queries), so only the user-point path needs the wrapper guard (L-1). Documented to make the assurance boundary explicit; `getUserPoint` likewise faithfully mirrors `veOLAS` OOB semantics. *Fix:* none.
- **I-15 — Cross-cutting governance / deployment notes:**
  - **Stale provenance comments** (`GovernorOLAS.sol:18`, `utils/GovernorTimelockControl.sol:2`): the headers claim OZ "used as is, version 4.8.3" / "(last updated v4.6.0)" on a `GovernorTimelockControl` that is a *fork* adding `governorDelay`/`updateGovernorDelay` and replacing `getMinDelay()` with `governorDelay` in `queue()`. Misleading to a diff-based reviewer. *Fix:* mark it a modified fork.
  - **`GovernorTimelockControl.updateTimelock` does not re-validate `governorDelay >= newTimelock.getMinDelay()`** (`:173-180`), and `governorDelay` can independently drift below `minDelay` if the Timelock raises `minDelay` via `updateDelay`. Both make `queue()` revert (`scheduleBatch` requires `delay >= minDelay`) — a **self-inflicted liveness** condition that fails safe (never under-delays) and is governance-recoverable. *Fix:* take `max(governorDelay, getMinDelay())` in `queue()`, or re-check the floor in `updateTimelock`.
  - **`Timelock` constructor grants the deployer EOA `TIMELOCK_ADMIN_ROLE`** (`Timelock.sol:11`): a delay-bypassing master key during the bootstrap window. Mitigated on-chain by the deployment renouncing it with a `hasRole == false` assertion (OZ v4.8 opt-in pattern). *Fix:* to remove the window entirely, pass `address(0)` as admin.
  - **`DeploymentFactory.deployOLAS/deployVeOLAS` lack a one-shot guard** (`:51, 73`): a second call with a different salt overwrites the stored address pointer (a same-salt repeat reverts safely via Create2). *Fix:* add `if (olasAddress != address(0)) revert AlreadyDeployed();`.
  - **`BridgedERC20` single-step transferable `owner` is an uncapped mint/burn authority** (`:30-55`): correct under the intended mediator-owned design, but a mistyped `changeOwner` is irrecoverable. *Fix:* two-step handover; document that `owner` must be the bridge mediator, never an EOA.
  - **`WormholeRelayerTimelock` ignores the `approve()` return value** (`:292`): safe for OLAS (which reverts on failure) but unsafe for non-standard ERC20s and leaves no allowance reset. *Fix:* `SafeERC20.forceApprove` / 0-then-amount.
  - **`FxERC20RootTunnel.setFxChildTunnel` is a permissionless one-shot**: a front-run only causes a redeployable DoS (mint authority is independently gated by the MPT-receipt proof + mediator ownership). Current deploy ordering is safe. *Fix (optional):* override with `onlyOwner`.

---

## 2. Decisive resolution of the two cross-chain `>Medium` candidates

Two cross-chain questions had the potential to be High-severity (an *unauthorized* L2 execution). We resolved both directly against the bytecode-level parse logic rather than by symptom.

**(a) Verifier-vs-executor parser divergence — NOT a finding.** The hypothesis was that the Guard's verifier and the L2 executor could be made to disagree on record boundaries, so the Guard authorizes record set X while the executor performs set Y → an arbitrary unauthorized call. We compared the two parsers field-by-field. The record layout is `target(20) | value(12) | payloadLength(4) | payload(payloadLength)`. The verifier (`VerifyBridgedData`) advances its cursor `20 → +16 → +payloadLength`; every executor (`HomeMediator`, `FxGovernorTunnel`, `BridgeMessenger`) advances `20 → +12 → +4 → +payloadLength`. These are **identical** (`20 + 16 == 20 + 12 + 4 == 36`): both read `payloadLength` from the same offset and both advance by `36 + payloadLength` per record, so they segment every buffer into **exactly the same records**, and the verifier checks the selector on the very `payload` the executor will call. There is **no reachable divergence**. (The apparent "different stride" is only that the verifier folds the value+length skip into one `mload`; the offsets coincide.)

**(b) Inner `value` not bound by the allowlist — REAL but Low.** Confirmed and reported as **L-5**: the verifier skips `value`, the executor forwards `target.call{value}` bounded by the mediator's balance. Because the trigger is the threshold-trusted CM, the destination is an allowlisted target, and the amount is balance-bounded, this is a bounded gap, not an unprivileged or arbitrary-recipient theft.

---

## 3. Architecture note — the security model rests on the Community-Multisig guard

We surface one load-bearing trust property for the DAO to own explicitly (not a code defect):

The Community Multisig (CM) holds `PROPOSER` + `EXECUTOR` (+ `CANCELLER`) directly on the Timelock, and
the post-vote delay (`governorDelay`) is enforced only on the Governor's `queue()` path. With the
Timelock's own `minDelay` low, the CM can `schedule(..., minDelay)` + `execute` straight on the Timelock,
bypassing `governorDelay` entirely. The **only** containment on this direct CM path is `GuardCM`'s
target/selector allowlist (the guard inspects `schedule`/`scheduleBatch` to the Timelock; the CM's
`CANCELLER` lets it cancel queued Governor proposals). Combined with L-6 (the CM can participate in
releasing the guard) and L-5/I-6 (an allowlisted tuple permits arbitrary value/args), the practical
security boundary of the entire system is: *the honesty of the CM threshold signers plus the correctness
and curation of the `GuardCM` allowlist.* This is an intentional emergency/operational design, standard
for this DAO, but it should be a conscious, monitored invariant — `GuardCM` is security-critical, and the
Timelock `minDelay` is best kept strictly `> 0` as a universal floor.

We also note a benign architectural split worth tracking: the live Governor reads voting power through
`wveOLAS` (guarded), while `VoteWeighting` reads the raw `veOLAS` directly. `VoteWeighting` consumes the
*current* `getLastUserPoint(...).slope`/`lockedEnd` rather than the historical `getPastVotes`, so the L-1
index-0 guard is not on its code path and we found no concrete exploit from the split — but two consumers
of the same token relying on different guard regimes is a consistency hazard to keep in view.

---

## 4. Clean-coverage note

Examined and found correct as designed (beyond the Info notes):

- **Vote-escrow withdrawals (`veOLAS.withdraw`, `:510-535`)** read only per-account state and are independent of the global supply loop and of every accounting finding above — no funds are at risk from any L-/I- finding.
- **Deployed governance routing** is wired to the `wveOLAS` wrapper, whose guards suppress the raw `veOLAS` view defect (L-1); no in-repo contract consumes the raw historical views.
- **All value-bearing `VoteWeighting` paths** are independently guarded by `mapRemovedNominees` (re-add double-blocked, stale ids revert on `getNominee`), so the bookkeeping findings (L-2, L-4, I-1) cannot be chained into fund or vote corruption.
- **`GuardCM` access control / pause semantics** (`onlyOwner` setters, `NoDelegateCall`, `NoSelfCall`, schedule-scope verification) are correct; the in-repo bridge verifiers are read-only and storage-layout-compatible; the Arbitrum verifier's `l2CallValue == 0` + refund-equality invariants make the "unsafe" retryable variant economically safe.
- **`OLAS` access control** (`mint`/`burn`/`changeMinter`/`changeOwner`) is correct and the inflation arithmetic is sound under checked math; the only notes are the documented supply-vs-emission semantics (I-3) and the no-op-mint convention (I-4).
- **Cross-chain sender authentication** is enforced on every relay (`HomeMediator` checks `AMBContractProxyHome` + `IAMB.messageSender == foreignGovernor`; the Wormhole path dedups on delivery hash; the Optimism/Gnosis paths rely on the bridge's own at-most-once `xDomainMessageSender`/`messageSender`). The arbitrary `target.call{value}` in each relay is by design — its safety lives in this upstream sender auth, which is present and correct.

---

## 5. Methodology & coverage

Every in-scope production contract was reviewed against a full correctness checklist (access control,
reentrancy/CEI, arithmetic and `unchecked` blocks, state-machine invariants, external-call return and
unbounded-returndata handling, DoS/gas, signature/replay, cross-chain message authentication, vote-escrow
decay and past-timestamp math, gauge/weighting accounting, timelock/governor invariants, token mint caps,
initialization, and oracle/price-consumer safety). High-consequence custom surfaces (`veOLAS`,
`VoteWeighting`, `GuardCM`, the bridge verifiers, and the cross-chain relays) were reviewed under
two independent adversarial review passes, and each candidate finding was independently re-verified
against the source before inclusion; the two cross-chain `>Medium` candidates were resolved at the parse-logic level
(§2). All findings are our own independent analysis. The deprecated `buOLAS` token is excluded from scope.

— audit-claude
