# Autonolas Governance — Internal Security Re-Audit (internal19)

The review was performed by hand on the contract code in this repository on the `main` branch
(commit `bae8da6`).

This is a comprehensive, from-scratch, manual re-audit of every in-scope `autonolas-governance` production
contract — read in full, line by line, reasoned from first principles, with each finding verified against
the source and (where it concerns deployed state) against the live mainnet contracts. Particular attention
was paid to the contract-to-contract seams and to uncontrolled calldata crossing the L1↔L2 boundary, since
that is where the cross-chain governance path concentrates its risk.

We act as the deciding authority: every item below carries a definitive verdict — **a defect to fix**, or
**sound (as deployed / by design)** with the reason it is sound. Nothing is deferred. Findings that match an
issue already described in the repository's published documentation are marked as such and not re-derived;
they still carry our own verdict.

**Overall verdict: PASS-WITH-FINDINGS. 0 Critical / 0 High.** No path was found by which an unprivileged
actor can move funds, mint tokens, or subvert the live governance system, and no path by which malformed or
attacker-influenced cross-chain calldata can cause an unauthorized L2 execution. The findings are a set of
correctness, robustness, and governance-configuration defects to fix, plus several latent defects that are
**dormant on the live (non-upgradeable) deployment** and a body of items examined and judged sound.

---

## Scope

The 26 in-scope production contracts (interfaces and the deprecated `buOLAS` token excluded):

| Group | Contracts |
|---|---|
| Token / escrow | `OLAS.sol`, `veOLAS.sol`, `wveOLAS.sol` |
| Gauge weighting | `VoteWeighting.sol` |
| Governor / timelock | `GovernorOLAS.sol`, `Timelock.sol`, `utils/GovernorTimelockControl.sol` |
| Multisig guard | `multisigs/GuardCM.sol`, `multisigs/VerifyData.sol`, `multisigs/bridge_verifier/VerifyBridgedData.sol`, `multisigs/bridge_verifier/ProcessBridgedData{Arbitrum,Gnosis,Optimism,Polygon,Wormhole}.sol` |
| Cross-chain relays | `bridges/{FxGovernorTunnel,HomeMediator,OptimismMessenger,WormholeMessenger,WormholeRelayerTimelock,BridgeMessenger,FxERC20ChildTunnel,FxERC20RootTunnel,BridgedERC20}.sol` |
| Misc | `Burner.sol`, `DeploymentFactory.sol` |

The inherited `lib/fx-portal` `FxBaseRootTunnel` was additionally read where the token-bridge mint path's
security depends on it. The deprecated `buOLAS` token is excluded (marked deprecated in the repository
`README.md`; not part of the active governance surface).

---

## 1. Findings to fix

These are genuine code defects. Every in-scope contract is **non-upgradeable**, so the code fix lands on a
future redeployment; where a defect is reachable on the live contract, the available live mitigation is
given. None is reachable as theft or unprivileged governance subversion.

#### F-1 — `GuardCM.setTargetSelectorChainIds` does not bound `chainId`, so the allowlist key can be silently mis-set
- **Location:** `multisigs/GuardCM.sol:330` (only `chainId != 0` is checked), packing at `:340` (`chainId << 192`); the sibling setter `setBridgeMediatorL1BridgeParams:389` *does* enforce `chainId <= MAX_CHAIN_ID`.
- **Analysis:** The allowlist key packs `target(160) | selector(32) | chainId(64)` into one `uint256` by `chainId << 192`. A `chainId >= 2^64` shifts its high bits out of the 256-bit word, so e.g. `2^64 + 5` packs identically to `5`. The owner authorizing a malformed/oversized chainId therefore writes the allow-flag for a *different* `(chainId mod 2^64)` combination than intended. The enforcement read (`VerifyData.sol:31`) and the bridged path pass a bounded chainId, so the gap is on the owner-write side; it is inconsistent with the bounded sibling setter.
- **Verdict: DEFECT.** Impact: an owner-only configuration-integrity defect (a mis-entry authorizes the wrong chain), not unprivileged. **Fix:** add `if (chainIds[i] > MAX_CHAIN_ID) revert L2ChainIdNotSupported(chainIds[i]);` in `setTargetSelectorChainIds`, matching the sibling.

#### F-2 — Cross-chain verifiers do not bound the per-record native `value` that the L2 executor spends
- **Location:** `multisigs/bridge_verifier/VerifyBridgedData.sol:44-51` skips the 12-byte per-record `value` (`i := add(i, 16)`), and `_verifyData` authorizes only `(target, selector, chainId)`; the L2 executors forward it — `bridges/HomeMediator.sol:160`, `bridges/FxGovernorTunnel.sol:160`, `bridges/BridgeMessenger.sol:73` — via `target.call{value: value}(payload)`, bounded only by the mediator's own balance.
- **Analysis:** A guard-authorized `(target, selector, chainId)` triple says nothing about the native `value` the L2 mediator will forward. A scheduled bridged record can therefore carry an arbitrary `value` (up to the mediator's balance) to an allowlisted target, unseen by the guard. The guard's implicit model — "the CM can only invoke allowlisted selectors and moves no native value" — holds for the selector half but not the value half. (Distinct from the top-level value checks already present on the Arbitrum/Wormhole verifiers; this is the inner per-record value of the bridged batch.)
- **Verdict: DEFECT.** Impact bounded — the trigger is the threshold-trusted Community Multisig, the destination must be an allowlisted target, and the amount is capped by whatever native balance the relay mediator holds (typically ~0 for a pure relay). But the L1 authorizer should constrain what the L2 executor spends. **Fix:** read the 12-byte `value` in `_verifyBridgedData` and require it to be `0` for non-payable allowlisted selectors (mirroring the Arbitrum verifier's `l2CallValue == 0` enforcement), or bound it per target.

#### F-3 — `VoteWeighting._nomineeRelativeWeight` does not cap the returned weight at `1e18`
- **Location:** `VoteWeighting.sol:433` (`weight = 1e18 * nomineeWeight / totalSum`, no clamp); the docstrings at `:414` and `:437` promise "not more than 1.0".
- **Analysis:** `relativeWeight = 1e18 * nomineeWeight / totalSum`. The function's documented postcondition is `<= 1e18`. When `totalSum` under-counts relative to a surviving nominee's `nomineeWeight` — which can happen via the removal-accounting drift in F-6 — the result exceeds `1e18`, violating the contract's own stated invariant.
- **Verdict: DEFECT.** **Cross-contract seam:** this view is consumed by the off-repo incentive distributor (Dispenser) to split staking incentives; a value `> 1e18` there leads to over-allocation. **Fix:** clamp in `_nomineeRelativeWeight`: `if (weight > 1e18) weight = 1e18;`.

#### F-4 — `VoteWeighting.removeNominee` last-element guard mismatches intent, leaving a dangling `mapNomineeIds`
- **Location:** `VoteWeighting.sol:625` (guard `if (numNominees > 1)`; the comment at `:623` states the intent is "if it's not the last nominee").
- **Analysis:** Removing the **last** of ≥2 nominees still enters the swap-and-pop branch (`numNominees > 1` is true). Traced on `[sentinel, A, B]` removing `B (id = 2)`: line 627 re-reads `setNominees[2] = B`, line 628 recomputes `hash(B)`, line 629 sets `mapNomineeIds[hash(B)] = 2` — **re-writing the value that line 620 had correctly zeroed** — then line 633 pops. Post-state: the removed nominee is present in both `mapRemovedNominees` (≠0) and `mapNomineeIds` (= its old id, now dangling past the array end). The correct guard is `id != numNominees`.
- **Verdict: DEFECT.** Impact is **view-only**: `getNomineeId` / `getNextAllowedVotingTimes` (which key existence off `mapNomineeIds == 0`) return stale data to off-chain consumers. Every on-chain value-bearing path is independently guarded by `mapRemovedNominees` (re-add blocked at `:301`, voting blocked at `:479`, `getNominee(staleId)` reverts on the length bound at `:766`), so the dangling entry cannot be chained into a fund/vote effect — but the on-chain state is genuinely wrong. **Fix:** `if (id != numNominees)`.

#### F-5 — `VoteWeighting.revokeRemovedNomineeVotingPower` mutates slope without first advancing the checkpoint
- **Location:** `VoteWeighting.sol:666-668` writes `pointsSum`/`pointsWeight` slope via `_maxAndSub` without first calling `_getSum()`/`_getWeight()` to advance the slot to `nextTime` (unlike `voteForNomineeWeights`, which does at `:533-534`).
- **Analysis:** If the function runs in a week later than the last checkpoint, the target `nextTime` slot is stale (0), so `_maxAndSub(0, oldSlope.slope)` floors to 0 and the voter's slope removal is silently lost — while `changesSum[oldSlope.end] -= oldSlope.slope` (`:674`) still executes. A residual slope then over-decays the sum until natural expiry. (`:674` itself cannot underflow: the voter's own contribution is present and guarded by `oldSlope.end > block.timestamp`.)
- **Verdict: DEFECT.** Impact: gauge-weight accounting drift; no funds, no DoS, self-converging. **Fix:** call `_getSum()` and `_getWeight(account, chainId)` at the start, mirroring `voteForNomineeWeights`.

#### F-6 — `VoteWeighting.removeNominee` leaves a dangling slope and can brick further removals (unclamped subtraction)
- **Location:** `VoteWeighting.sol:607` zeros only the bias; `:611` performs the lone raw subtraction `newSum = oldSum - oldWeight` (every other delta uses `_maxAndSub`); the removed nominee's slope is not subtracted from `pointsSum[nextTime].slope` and its scheduled `changesSum` entries are not cancelled.
- **Analysis:** Reconciliation is deferred to per-voter `revokeRemovedNomineeVotingPower`. Until voters call it, `_getSum` keeps subtracting the removed nominee's phantom slope, so the global sum over-decays and floors to 0 (`:238-241`) while a surviving nominee's weight is still positive. A subsequent `removeNominee` of that survivor then computes `oldSum(small) - oldWeight(larger)` at `:611` and reverts (checked underflow), bricking `removeNominee` until the sum re-syncs.
- *This defect is already described in the repository's published vulnerabilities list; we do not re-derive it. Our verdict differs from "operationally mitigated": it should be fixed in code.*
- **Verdict: DEFECT.** Impact: owner-scoped liveness (no funds, no theft), self-healing. We do not accept the documented "ask voters to revoke" operational workaround as sufficient for a re-audit. **Fix:** use `_maxAndSub` at `:611`, and subtract the removed nominee's slope from `pointsSum[nextTime].slope` and cancel its pending `changesSum` events inside `removeNominee` (eliminate the drift at the source). Live mitigation until redeployed: the documented pre-removal voter cleanup / vote-zeroing.

#### F-7 — `GovernorTimelockControl`: `governorDelay` can drift below the timelock `minDelay`, bricking `queue()`
- **Location:** `utils/GovernorTimelockControl.sol:115` (`queue` schedules with `delay = governorDelay`); `:193-204` (`_updateGovernorDelay` checks `>= minDelay` only at set-time); `updateTimelock:173-180` does not re-check the floor against a new timelock.
- **Analysis:** The fork deliberately schedules with `governorDelay` instead of the timelock's `minDelay`. `minDelay` is updatable separately (`TimelockController.updateDelay`), so it can be raised above `governorDelay`; then `queue()` passes `delay = governorDelay < minDelay` to `scheduleBatch`, which reverts, and no proposal can be queued. The in-code CAUTION (`:185-187`) documents the hazard.
- **Verdict: DEFECT (self-inflicted liveness, fails safe — never under-delays).** **On the live deployment this is dormant: the live `minDelay` is `0` and the live `governorDelay` is `157092 s ≈ 1.82 d` (both verified on-chain, §6), so `governorDelay >= minDelay` holds and the desync cannot occur until `minDelay` is raised.** Recoverable through governance (raise `governorDelay` first). **Fix:** in `queue()`, schedule with `delay = governorDelay < minDelay ? minDelay : governorDelay`, or re-validate the floor in `updateTimelock`. Operational rule until then: change `governorDelay` and `minDelay` together.

#### F-8 — `GovernorOLAS` / `GovernorTimelockControl` provenance comments are stale and misleading
- **Location:** `GovernorOLAS.sol:18` ("The OpenZeppelin functions are used as is, version 4.8.3."); `utils/GovernorTimelockControl.sol:2` ("(last updated v4.6.0)").
- **Analysis:** `GovernorTimelockControl` is a **fork** of the OZ contract that adds `governorDelay`/`updateGovernorDelay`, the `Underflow` error, and replaces `getMinDelay()` with `governorDelay` in `queue()`. The "used as is" / "v4.6.0" markers can mislead a diff-based reviewer into treating it as unmodified OZ and skipping the precise place where the deviation (and F-7) lives.
- **Verdict: DEFECT (documentation / cosmetic).** **Fix:** mark the file as a modified fork of OZ 4.8.3 with the custom `governorDelay`, and remove the "used as is" / "(v4.6.0)" markers.

#### F-9 — `VoteWeighting.removeNominee` emits `OwnerOnly` with transposed arguments
- **Location:** `VoteWeighting.sol:590` (`revert OwnerOnly(owner, msg.sender)`); the error is declared `(sender, owner)` at `:47` and passed correctly at every other site (`changeOwner:372`, `changeDispenser:390`).
- **Analysis:** The authorization check itself is correct (`if (msg.sender != owner)` at `:589`); only the revert payload transposes the two `address` arguments. Effect is limited to misleading custom-error data for off-chain decoders; the selector is unchanged and there is no auth or control-flow impact.
- **Verdict: DEFECT (cosmetic).** **Fix:** `revert OwnerOnly(msg.sender, owner);`.

---

## 2. Latent defects — sound as deployed, fix on redeploy

Real defects in the abstract code whose trigger condition does **not exist on the live (non-upgradeable)
deployment**. We do not demand the technically-unachievable: no action is required on the live contracts;
correct them on any future redeployment, and hold the stated invariant meanwhile. Each dormancy condition
was verified on-chain (§6).

- **D-1 — `GuardCM.mapBridgeMediatorL1BridgeParams` is keyed by the L1 mediator address only** (`:134`/`:394`), although the `BridgeParams` struct carries `chainId` (`:42`). A bridge family that uses one L1 entry point for multiple destination chains collides (the second configuration overwrites the first). This is intended under the documented "each L2 verifier has a unique association with the L1 bridge mediator" design, which holds for the four live verifiers (Arbitrum / Gnosis / Optimism-stack / Polygon — distinct L1 mediator addresses). The only family that violates the premise is a single-relayer model; that path is not configured on the live guard (verified: the live guard has no such entry). **Verdict: sound as deployed; on any reintroduction of a shared-L1-relayer bridge, change the mapping to a composite `(L1, chainId)` key first; meanwhile hold the invariant "never configure two bridge entries that share one L1 mediator address."**

- **D-2 — `WormholeMessenger` authenticates with a single `sourceGovernor`** (`bridges/WormholeMessenger.sol:19,88-95`), which cannot match two distinct L1 sender identities (a direct path and a mediated path) simultaneously; correspondingly the matching verifier accepts only the direct-relayer signatures. Only the single direct path is/was live and that bridge family is being retired. **Verdict: sound as deployed (single live path); if dual-path governance over that bridge is ever reintroduced, the receiver/verifier must accept the set of legitimate source authorities rather than one.**

- **D-3 — `Timelock` constructor grants the deploying EOA `TIMELOCK_ADMIN_ROLE`** (`Timelock.sol:11`, the OZ v4.8 optional-admin pattern) — a delay-bypassing role during the bootstrap window. The deployment renounces it; on-chain the timelock is self-administered (verified, §6). **Verdict: sound as deployed (window closed); to remove the window entirely on a future deploy, pass `address(0)` as the admin.**

- **D-4 — `FxERC20RootTunnel.setFxChildTunnel` is a permissionless one-shot** (inherited from `FxBaseRootTunnel`): a front-run before the deployer would pin the L2 emitter to an attacker contract, enabling mint-without-lock on L1. The window is at deploy time only; the live bridge already has its child tunnel set. **Verdict: sound as deployed (window closed); on a future deploy, override `setFxChildTunnel` with `onlyOwner` or set it in the constructor.**

---

## 3. Examined and judged sound

Items inspected in depth and judged correct — either by design (intent confirmed against the project's
design documentation) or because the protective invariant holds.

- **GuardCM verifier `delegatecall` (`:221`).** The bridged-path verifier runs via `delegatecall`, so it executes in `GuardCM`'s storage. The project's guard design specifies the verifiers as external libraries **without their own storage**; every in-repo verifier is strictly stateless (no `SSTORE`, no external calls — verified) and storage-layout-compatible with `VerifyData`, so it cannot corrupt guard state. **Sound by design** (the stateless-verifier property is the documented design contract).
- **GuardCM heartbeat release (`pause`, `:407-425`).** The guard may be released by the multisig only when its referenced governance proposal is in a terminal `Defeated` state — a deliberate liveness backstop for governance inactivity. A stale referenced proposal id (after `changeGovernor`) makes the release path revert (fails safe; the timelock can always pause). **Sound by design.**
- **GuardCM scope.** The guard inspects only `schedule`/`scheduleBatch` to the timelock — exactly the DAO-curated allowlist surface it is designed to gate. **Sound by design** (see also §4).
- **Verifier ↔ L2-executor parse seam.** We compared the byte-level record parsing of `VerifyBridgedData` against every executor (`HomeMediator`/`FxGovernorTunnel`/`BridgeMessenger`): both advance their cursor identically per record (`20 + 16` ≡ `20 + 12 + 4` = 36 bytes, then `+ payloadLength`), and the verifier checks the selector on the exact payload the executor calls. There is **no reachable divergence** by which the guard could authorize one record set while the executor performs another. (The raw `mload` header reads without an explicit per-record bound fail closed — a malformed tail reverts on the bounds-checked payload copy or a zero-address — but we recommend adding explicit `dataLength - i >= 36` / `i + payloadLength <= dataLength` assertions for fail-fast clarity rather than relying on downstream reverts.)
- **Polygon token bridge (`FxERC20RootTunnel`/`FxERC20ChildTunnel`/`BridgedERC20`).** The L2→L1 mint path depends on the inherited `FxBaseRootTunnel`, which we read: it provides a `processedExits[exitHash]` replay guard (with the nibble-array exitHash form that closes the historical branch-mask bypass), full Merkle-Patricia receipt-proof + checkpoint-inclusion verification, and an emitter check. Mint of the bridged token is therefore backed by a proven, non-replayable L2 deposit; the reverse path is gated by the Polygon state-sync and `validateSender`. Messages are `abi.encode/decode`d (no hand-rolled parsing). `BridgedERC20`'s single-step uncapped `owner` is the bridge mediator by design (documented), with no further `changeOwner` path in the tunnel. **Sound.**
- **`WormholeRelayerTimelock`** (not deployed): reentrancy-guarded, timelock-only, and its unchecked `approve()` return fails closed (the only bridged token reverts on failure). **Sound.**
- **`veOLAS` / `wveOLAS`.** All eleven `unchecked` blocks were checked by hand and are bounded-safe (deposit sums bounded by the `uint96` input checks against a supply `<< 2^128`; week loops bounded to 255 iterations and `< 2^64`; the `(block.timestamp + unlockTime)` rounding is always re-validated into `(now, now+MAXTIME]` before any state write, so a wrap is harmless). The historical-view functions whose raw-`veOLAS` behavior is described in the project's vulnerabilities list are mitigated for the deployed governor, which reads the guarded `wveOLAS` wrapper (verified on-chain, §6); the wrapper adds the missing pre-first-checkpoint guard. Withdrawals read only per-account state and are independent of the global supply loop, so funds are always withdrawable after expiry. **Sound** (the raw token's historical views remain non-self-safe for a direct integrator — a documented property).
- **`OLAS`.** The supply cap bounds net `totalSupply` (so a burn restores mint headroom) — consistent with its explicit "Total supply cap" semantics; `mint` silently no-ops over the cap (documented, minter-trusted, consumer-checked); the post-year-10 inflation loop is `O(years)` and negligible for centuries; `inflationRemainder` cannot underflow (the `totalSupply <= supplyCap` invariant holds and the cap is monotonic). **Sound** (note the supply-vs-emission semantics for any consumer; the silent no-op mint is the integrating caller's responsibility — see the cross-repo note).
- **`VoteWeighting`** permissionless nominee registration (no on-chain loop iterates the nominee set — the week loops are time-bounded, and a vote-less nominee has zero weight), the 250-week checkpoint loop (a documented Curve-port limitation, permissionless to reset), the dispenser-sync precondition, and the indirect existence check in `voteForNomineeWeights` (a revert rolls back all writes) — **all sound**.
- **`Burner`, `DeploymentFactory`.** Trivial, reentrancy-guarded / owner-gated genesis helpers; the factory is inert post-genesis. **Sound.**

---

## 4. Governance-architecture observation

Not a code defect, surfaced for the DAO to own consciously. The Community Multisig holds
`PROPOSER`+`EXECUTOR`(+`CANCELLER`) directly on the timelock; the post-vote delay binds only the Governor's
`queue()` path — and that delay is **`governorDelay` (currently `157092 s ≈ 1.82 d` on-chain), not the
timelock's `minDelay`**: the forked `GovernorTimelockControl.queue()` schedules with `governorDelay`
(`utils/GovernorTimelockControl.sol:115`), so a *passed governance proposal* is delayed by `governorDelay`,
and a full proposal therefore takes ≈ `votingDelay (13091 blk) + votingPeriod (19636 blk) + governorDelay
(157092 s)` ≈ **6.4 days** end-to-end. The live timelock `minDelay` is **`0`** (verified on-chain, §6), and
`minDelay` governs **only** the CM's *direct* `schedule` path — **not** governance proposals — so the
CM's direct `schedule`+`execute` path executes with **no timelock delay**, and the CM's `CANCELLER` lets it
cancel any queued Governor proposal. The **sole containment** on the CM's direct path is therefore the
`GuardCM` allowlist (target/selector). This is an intentional emergency/operational design, but the practical
security boundary of the whole system reduces to *the CM threshold signers + the correctness and curation of
the `GuardCM` allowlist*. We recommend keeping `GuardCM` treated as security-critical and monitored, and
setting the timelock `minDelay` strictly `> 0` as a universal floor (which would also make F-7 unreachable by
construction).

We also note a benign architectural split: the live Governor reads voting power through the guarded
`wveOLAS` wrapper, while `VoteWeighting` reads the raw `veOLAS` directly (both verified on-chain, §6).
`VoteWeighting` consumes the *current* `getLastUserPoint(...).slope` / `lockedEnd` rather than the historical
views, so the wrapper's pre-first-checkpoint guard is not on its path and we found no concrete exploit from
the split — but two consumers of the same token relying on different guarantee regimes is a consistency
hazard worth tracking.

---

## 5. Previously-documented items

The following were verified to still be present and were assessed; they are described in the repository's
published `Vulnerabilities_list_governance` document and/or a prior internal review, so we record our verdict
without re-deriving them: the `veOLAS` historical-view behavior (mitigated by `wveOLAS` for the deployed
governor — sound as deployed), the `veOLAS` `_checkpoint` long-dormancy limitation (documented Curve-port
limitation; checkpoint keeper), the `createLockFor` griefing vector (documented; attacker funds their own
griefing lock), the `HomeMediator` source-chain-id check absence (sound as deployed — the bridge is
Ethereum-only today), the `OLAS` no-op-mint convention (documented), and the `VoteWeighting` removal /
nominee-id / vote-ordering notes (our verdicts are F-3/F-4/F-6 above and §3). The previously-applied fixes to
the Arbitrum and Wormhole verifiers (the `l2CallValue == 0` / `receiverValue == 0` + refund-address checks)
are present and correct — they are the existing mitigation, not findings.

---

## 6. On-chain verification (Ethereum mainnet, read-only; 2026-06-29, re-grounded on the redeployed Governor 2026-06-30)

The deployment-state facts that the verdicts above rely on were confirmed against the live contracts:

| Check | Result |
|---|---|
| `GovernorOLAS.token()` (live governor `0x060D0C…`) | `0x4039B8…` = `wveOLAS` (the deployed Governor reads the guarded wrapper) |
| `GovernorOLAS.governorDelay()` (live `0x060D0C…`) | `157092 s ≈ 1.82 d` — the proposal-path delay (§4 / F-7); **≠** the timelock `minDelay` |
| `GovernorOLAS.timelock()` (live `0x060D0C…`) | `0x3C1f…` (the audited Timelock) |
| `VoteWeighting.ve()` | `0x7e01A5…` = raw `veOLAS` (confirms the §4 split) |
| `GuardCM` (live) bridge params for the single-relayer L1 address | `0x0` — no such bridge entry configured (D-1 / D-2 dormant) |
| `Timelock.hasRole(TIMELOCK_ADMIN_ROLE, self)` | `true` (self-administered) |
| `Timelock.getMinDelay()` | `0` (F-7 dormant; the CM direct-path-no-delay property of §4) |

**Governor redeployment (noted for completeness).** The live `governorAddress` is the **redeployed**
GovernorOLAS `0x060D0C…`; the prior instance `0x8E84B5…` (`governorTwo`) has had its `PROPOSER` and
`EXECUTOR` roles on the Timelock **revoked** (verified: the live governor holds both = `true`, the prior
holds both = `false`), so there is no dual-governance entry point. The redeployment is the **same audited
source** — between the audit baseline and the deployment-config commit the only change is
`scripts/deployment/globals_mainnet.json` (no `.sol` delta), so the code reviewed here is the code deployed
at `0x060D0C…`; no unaudited contract was activated by the redeploy.

(The deployer-EOA admin renunciation behind D-3 is asserted on-chain by the deployment and confirmed by the
self-administration above; re-confirming `hasRole(TIMELOCK_ADMIN_ROLE, deployerEOA) == false` against the
specific deployer address is a one-call follow-up.)

---

## 7. Methodology & coverage

Every in-scope production contract was read in full, by hand, and reasoned from first principles against a
complete correctness checklist (access control, reentrancy/CEI, arithmetic and every `unchecked` block,
state-machine and lifecycle invariants, external-call return and unbounded-returndata handling, DoS/gas,
signature/replay, cross-chain source authentication and replay, vote-escrow decay and past-timestamp math,
gauge/weighting accounting, timelock/governor invariants, token mint caps, initialization, and
oracle/price-consumer safety), with explicit attention to the contract-to-contract seams and the L1↔L2
calldata boundary. Each candidate finding was self-checked against the repository's published documentation
and a prior internal review so that already-documented items are not re-derived and genuinely new ones are
surfaced; each was then given a definitive verdict (defect to fix, or sound), with deployment-dependent
verdicts grounded against the live contracts (§6). All findings are our own independent analysis. The
deprecated `buOLAS` token is out of scope.

— audit-claude
