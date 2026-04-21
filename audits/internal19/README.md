# Internal audit 19 of autonolas-governance (post-C4A re-audit)

Repository: https://github.com/valory-xyz/autonolas-governance
Commit audited: `76bda389` (Merge PR #192 `address_audit18` → main)
Audit date: 2026-04-21
Deliverable style: internal template (C4A verification matrix + on-chain owner map + Vulnerabilities_list hygiene)
Prior reference: `audits/internal18/README.md`

## 1. Objectives

This audit is a **full re-audit** of `autonolas-governance` against the Code4rena (C4A) Olas 2026-01 external audit report:

- Map every applicable C4A finding to the governance repo and verify the fix in the current code.
- Build an on-chain owner map for all deployed governance contracts and run the Kelp-pattern / OpSec checks required by `AGENT-RULES.md`.
- Re-verify the 10 entries in `docs/Vulnerabilities_list_governance.md` against current code and update the hygiene table.
- Review internal18 findings — confirm they still hold on HEAD `76bda389` and check for anything missed.

Out of scope: off-chain bridge relayers, the Polygon FxPortal library itself (`lib/fx-portal`), Gnosis Safe core, and OpenZeppelin library sources. Inherited OZ / solmate code is trusted.

## 2. Scope

27 contracts, ~5142 LOC — unchanged from internal18. Numbers from internal18:

| Group | Contracts | ~LOC |
|---|---|---|
| Token / escrow | `OLAS`, `veOLAS`, `wveOLAS`, `buOLAS`, `Burner` | 1497 |
| Governor & timelock | `GovernorOLAS`, `GovernorTimelockControl`, `Timelock` | 340 |
| Gauge controller | `VoteWeighting` | 822 |
| Multisig guard | `GuardCM`, `VerifyData`, `VerifyBridgedData` | 570 |
| Bridge verifiers | `ProcessBridgedData{Arbitrum,Gnosis,Optimism,Polygon,Wormhole}` | ~470 |
| L2 receivers | `FxGovernorTunnel`, `HomeMediator`, `OptimismMessenger`, `WormholeMessenger`, `BridgeMessenger` | 605 |
| Wormhole relayer | `WormholeRelayerTimelock` | 312 |
| Other | `FxERC20{Root,Child}Tunnel`, `BridgedERC20`, `DeploymentFactory` | 364 |

All of these were read fresh in this session (task #79).

## 3. Streams / workflow

1. **C4A mapping** — sub-agent triage of all 11H + 12M + 15L findings → identify governance-scope items.
2. **Code-level C4A fix verification** — open every changed file and confirm fix is present at the referenced line.
3. **Fresh read of all 27 contracts** (`contracts/**/*.sol`) — look for anything internal18 missed, and re-verify their manual findings on HEAD.
4. **On-chain verification** via Ethereum mainnet RPC (`cast call`) — Timelock roles, multisig thresholds + owners, governor wiring, owner of all core contracts.
5. **Vulnerabilities_list_governance.md hygiene** — re-check all 10 entries against code.
6. **Internal18 findings check** — for each internal18 finding, confirm status on HEAD.

## 4. C4A 2026-01 verification matrix (governance-scope only)

The C4A 2026-01 report covers all Olas repos. Every finding was classified by the contract it touches; only one item lands on a governance contract.

| C4A ID | Title | Target | Governance-scope? |
|---|---|---|---|
| **M-01** | **Arbitrum bridge — unchecked `l2CallValue` / refund addresses in `ProcessBridgedDataArbitrum`** | **autonolas-governance** | ✅ **YES** |

All other C4A entries (11H + 11M + 15L + disclosures) target other Olas repos and are out of scope for this audit.

**Result: exactly one C4A finding — M-01 — is governance-scope.**

### 4.1 C4A M-01 — Arbitrum bridge unchecked refund / value

**Original C4A finding.** `ProcessBridgedDataArbitrum.processBridgeData` decoded the Arbitrum retryable-ticket parameters (`l2CallValue`, `excessFeeRefundAddress`, `callValueRefundAddress`) but **did not validate them**. A CM-scheduled proposal could set `callValueRefundAddress` to an attacker address and, if `l2CallValue > 0`, the L2 would refund the non-executed call value to the attacker (or route excess fee refund to an attacker). The scenario drains ETH/refunds from the Timelock's L2 bridge escrow.

**Fix verified on code (tag: `76bda389`, file `contracts/multisigs/bridge_verifier/ProcessBridgedDataArbitrum.sol`):**

- Line 70 — `if (l2CallValue > 0) revert NonZeroValue(l2CallValue);`
- Line 75 — `if (excessFeeRefundAddress != l2Timelock) revert WrongL2BridgeMediator(excessFeeRefundAddress, l2Timelock);`
- Line 78 — `if (callValueRefundAddress != l2Timelock) revert WrongL2BridgeMediator(callValueRefundAddress, l2Timelock);`

`l2Timelock` is sourced from the `bridgeParams.bridgeMediatorL2` value in `GuardCM._verifySchedule` (i.e. `mapBridgeMediatorL1BridgeParams[target].bridgeMediatorL2`), which is a governance-controlled allowlist.

**Consistency with the Wormhole bridge (not a C4A finding, but same class):** `ProcessBridgedDataWormhole.sol` was tightened in the same commit set (`3e71631`):

- Line 93 — `if (refundChainId != REFUND_CHAIN_ID) revert WrongRefundChainId(refundChainId);` (`REFUND_CHAIN_ID = 2`, Ethereum mainnet in Wormhole chain-id space).
- Line 96 — `if (refundAddress != TIMELOCK) revert WrongRefundAddress(refundAddress);` (`TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE`).
- Line 102 — `if (receiverValue > 0) revert NonZeroValue(receiverValue);`

**Stale comment fix (internal17 side-observation):** `GuardCM.sol` now rejects `bridgeMediatorL2s[i] == address(0)` in `setBridgeMediatorL1BridgeParams` (line 378) and the misleading Arbitrum-specific comment has been removed.

✅ **C4A M-01 — FIXED AND VERIFIED.** No governance-scope C4A finding remains open.

## 5. On-chain verification (Ethereum mainnet, block-tip 2026-04-21)

RPC: QuikNode mainnet (§5.1) + publicnode (§5.2 role re-verification). Addresses sourced from `scripts/deployment/globals_mainnet.json`.

### 5.1 Governance contract owners

| Contract | Address | `owner()` / admin | Verdict |
|---|---|---|---|
| Timelock (`TimelockController`) | `0x3C1f…95fE` | Self-administered + Governor as admin | ✓ |
| GovernorOLAS | `0x8E84…B401` | Token: `wveOLAS` ✓; Timelock: `0x3C1f…95fE` ✓ | ✓ |
| OLAS | `0x0001…5CB0` | owner = Timelock ✓ | ✓ |
| veOLAS | `0x7e01…B7b3` | Ownerless (per design) | ✓ |
| wveOLAS | `0x4039…4B40` | Ownerless view wrapper | ✓ |
| buOLAS | `0xb09C…1f73` | owner = Timelock ✓ | ✓ |
| VoteWeighting | `0x9541…c5c1` | owner = Timelock ✓ | ✓ |
| GuardCM | `0x7bB7…6f3a` | owner = Timelock ✓; multisig = CM Safe `0x04C0…2570` ✓; governor = GovernorOLAS ✓ | ✓ |

All admin roles for governance contracts trace back to the Timelock multisig. No EOA-owned contracts, no Kelp-pattern `$294M` single-key situation in the governance repo.

### 5.2 Timelock roles (OpenZeppelin v4.6 TimelockController)

| Role | keccak256 | Held by | Verdict |
|---|---|---|---|
| `TIMELOCK_ADMIN_ROLE` | `0x5f58…6ca5` | Timelock self, GovernorOLAS | ✓ (self + governance) |
| `PROPOSER_ROLE` | `0xb09a…9cc1` | GovernorOLAS, **CM Safe** | ✓ by design — CM scheduling constrained by GuardCM allowlist, see §5.5 |
| `EXECUTOR_ROLE` | `0xd8aa…9e63` | GovernorOLAS, **CM Safe** (not open to `address(0)`) | ✓ by design — enables CM fast path; see §5.5 |
| `CANCELLER_ROLE` | `0xfd64…f783` | GovernorOLAS only (not CM) | ✓ |

Verified on mainnet (`publicnode` RPC, block-tip 2026-04-21) via `hasRole(bytes32,address)`:

```
hasRole(EXECUTOR_ROLE, address(0))    = false   // closed executor, not open-to-all
hasRole(EXECUTOR_ROLE, CM Safe)       = true
hasRole(EXECUTOR_ROLE, GovernorOLAS)  = true
hasRole(PROPOSER_ROLE, CM Safe)       = true
hasRole(PROPOSER_ROLE, GovernorOLAS)  = true
hasRole(CANCELLER_ROLE, CM Safe)      = false
hasRole(CANCELLER_ROLE, GovernorOLAS) = true
getMinDelay()                         = 0
```

### 5.3 Multisig composition

| Safe | Threshold | Owners | Kelp-pattern flag |
|---|---|---|---|
| CM Safe (`0x04C0…2570`) | **5 / 9** | 9 EOAs | ✓ healthy — 5-of-9 survives 4 lost keys |

The CM Safe 5/9 is unchanged from prior audits and is the only multisig in the governance admin chain.

### 5.4 Deployed vs. repo code — `governorDelay` not yet deployed

**Deployed Governor** (`0x8E84…B401`) fingerprinted via `cast call`:

- `name() = "Governor OLAS"`, `version() = "1"` ✓
- `votingDelay() = 13091 blocks` (~1.8 days), `votingPeriod() = 19636 blocks` (~2.7 days) ✓
- **`governorDelay()` → execution reverted** (selector `0x3a23ed5f`).
- Timelock `getMinDelay() = 0`.

⇒ The deployed Governor is the **OZ v4.x stock `GovernorTimelockControl`** — it does **not** have the new custom `governorDelay` field introduced by `contracts/utils/GovernorTimelockControl.sol`. Because `minDelay = 0`, the "timelock pause" on the deployed contract is 0 seconds; the effective delay between "vote passes" and "execute" is bounded only by the `delay` argument passed to `scheduleBatch` — which OZ stock reads from `_timelock.getMinDelay()`, not from a stored governor-side value.

Practical effect today: vote (3h delay + 2.7d voting) → execute immediately. This has been the live situation since governorTwo was deployed and is not a regression introduced by this PR; flagging it so the deployment of the re-audited code closes it.

**When the code in this repo is redeployed**, the custom `GovernorTimelockControl` (this repo lines 115–122) will pass `delay = governorDelay` to `_timelock.scheduleBatch`, and the constructor enforces `governorDelay ≥ minDelay`. `globals_mainnet.json` sets `governorDelay = 157092` (43.6 h). After deployment the effective timelock will be **≥ 43.6 h** — which is the intended design.

**Status / resolution.** **The new `GovernorOLAS` will be deployed ASAP**, gated only on sign-off from this audit round (all resolutions in hand, waiting for the green light). The deployment closes the `minDelay = 0` / missing-`governorDelay` gap noted above in a single step. Until that deployment lands, the live effective delay between "vote passes" and "execute" is 0 seconds on the Timelock side — tempered only by the Governor's voting period (~2.7 days) and voting delay (~1.8 days), which already provide a multi-day window for the community to react. No action beyond "ship the already-audited code" is required.

**Action (OpSec) for the Governor redeployment.** The role rotation on the Timelock must:

1. **Grant** `PROPOSER_ROLE`, `EXECUTOR_ROLE`, `CANCELLER_ROLE`, `TIMELOCK_ADMIN_ROLE` to the **new** `GovernorOLAS`.
2. **Revoke** `PROPOSER_ROLE`, `EXECUTOR_ROLE`, `CANCELLER_ROLE`, `TIMELOCK_ADMIN_ROLE` from the **old** `GovernorOLAS` (`0x8E84…B401`).
3. **Do NOT touch** the CM Safe's `PROPOSER_ROLE` / `EXECUTOR_ROLE` — these are load-bearing for the guarded fast path (§5.5) and must stay.
4. Run `GuardCM.changeGovernor(newGovernor)` so GuardCM's `governorCheckProposalId` state check reads against the correct Governor when CM tries to `pause()`.

The whole rotation must be scheduled through the **old** Governor — which is bounded by the current `minDelay = 0`. That 0-second delay is acceptable for a one-time admin transition, and is the reason the rotation should happen in a single coordinated proposal rather than piecemeal.

### 5.5 CM Safe holds `PROPOSER_ROLE` + `EXECUTOR_ROLE` — fast path guarded by GuardCM

**On-chain reality.** CM Safe holds **both** `PROPOSER_ROLE` and `EXECUTOR_ROLE` on the Timelock, and `minDelay = 0`. So CM Safe can schedule and execute a batch **in the same block** without any Governor vote.

This was observed live on 2026-01-21 (proof-of-design, not an incident):

| Tx | Block | CM action |
|---|---|---|
| [`0x89f5…f742332`](https://etherscan.io/tx/0x89f5f0ca534b50cc1499cefc8c1988ff7ffde0272c58f2ce943fabbfdf742332) | 24283059 | `scheduleBatch` → queues a call to Wormhole L1 message relayer `0x27428DD2…` |
| [`0xd7ee…b540055ae`](https://etherscan.io/tx/0xd7eedb13bf3642ab7221157155786c6d0645b5100445866202e0890b540055ae) | 24283094 (+7 min) | `executeBatch` → fires the queued call, relays to L2 |

The ~7 minute gap is operational cadence; the same block would have been permitted.

#### How this is still safe: GuardCM is the real access-control layer

CM's fast path is not unrestricted. Every Safe transaction is intercepted by `GuardCM.checkTransaction` (Gnosis Safe guard) BEFORE the Safe tx executes. The guard enforces, when active (`paused == 1`, the default):

1. **No `DelegateCall`** (`GuardCM.sol` line 263–265).
2. **No self-calls** on the multisig (lines 287–290).
3. **For `Timelock.schedule` / `scheduleBatch`**: every `(target, selector, chainId)` in the payload must be in `mapAllowedTargetSelectorChainIds` — enforced by `_verifySchedule` (line 189+). Bridged calls via `Timelock → L1 bridge mediator` go through an additional `IBridgeVerifier.processBridgeData` step that re-validates the L2 target+selector (the Arbitrum/Wormhole `ProcessBridgedData*` verifiers updated for C4A M-01 live on this path).
4. **`executeBatch` is not re-validated by the guard** — it doesn't need to be, because the Timelock's `hashOperationBatch` ties execute to the exact params that were validated at schedule time. CM cannot execute anything it didn't first schedule through the allowlist check.

The allowlist (`mapAllowedTargetSelectorChainIds`, `mapBridgeMediatorL1BridgeParams`) is only mutable by `setTargetSelectorChainIds` / `setBridgeMediatorL1BridgeParams`, both gated by `msg.sender != owner → revert` (line 308) where `owner = Timelock`. That means **only a Governor vote can expand what CM can touch on the fast path**. Within the allowlist, CM acts unilaterally — which is exactly the point.

#### Why this design exists

The CM 5-of-9 is the intended emergency / operational lane for time-sensitive governance actions: cross-chain bridge messages (like the Wormhole example above), pausing modules, routine admin batches that would otherwise stall behind a ~4.5-day Governor vote. This is documented behaviour in `GuardCM.sol` itself — the `pause()` function explicitly describes CM as an escape hatch when governance is inactive:

> *"The CM can request pausing the guard [if] there was a proposal to check if the governance is alive. If the proposal is defeated (not enough votes or never voted on), the governance is considered inactive for about a week."*
> — `GuardCM.sol:404–406`

So the layered model is:
- **Normal-path governance** (Governor vote): slow, ~4.5 days, broad power, gated by token-holder vote.
- **Fast-path operations** (CM via GuardCM): sub-minute, narrow power (allowlisted targets/selectors only), 5-of-9 human signatures.
- **Emergency escape** (CM calls `GuardCM.pause()`): only unlocks after the `governorCheckProposalId` proposal is *Defeated* — i.e. governance has demonstrably gone inactive.

Governor mutates the allowlist → Governor indirectly controls what CM can fast-path.

#### Governor redeployment interaction

When the new `GovernorOLAS` lands (§5.4, `governorDelay = 157092` / 43.6 h), `governorDelay` is the `delay` arg that the Governor passes to `scheduleBatch` for vote-originated proposals. It does **not** raise the Timelock's `minDelay`. CM continues to pass its own `delay`, bounded below by `minDelay` — which is still 0 unless the team separately schedules an `updateDelay` call. This is intentional: the Governor delay protects against rushed governance votes; the CM fast path stays fast because that's its whole reason to exist.

If the team ever wanted to enforce a minimum wait on CM-scheduled batches too, it would need a Governor proposal calling `Timelock.updateDelay(newMinDelay)` — which would slow both paths symmetrically.

#### Severity and real residual risk

**Severity:** Notes / documentation.

The role configuration is not a finding. The real attack surface is:

1. **`mapAllowedTargetSelectorChainIds` contents.** Every `(target, selector, chainId)` that Governor has voted into that map is a sub-minute CM-controlled action. Adding something broad (e.g., an `Ownable.transferOwnership` on any governed contract) would silently hand CM sweeping unilateral power.
2. **`mapBridgeMediatorL1BridgeParams` contents.** Same concern for bridged calls — the verifier and the L2 bridge mediator for each chain are governance-set.
3. **`governorCheckProposalId`.** Changed via `changeGovernorCheckProposalId(owner-only)`; governs when CM can unilaterally pause the guard. Stale or wrong proposalId could allow earlier-than-intended pausing (CM must submit a proposal that's then Defeated — still requires ~1 week of inaction plus the tx, so the bar is real, but worth checking the current value tracks a live "heartbeat" proposal convention).

**Recommended ongoing hygiene (not a finding):** periodically dump the contents of `mapAllowedTargetSelectorChainIds` and the three mediator maps, and review each entry against the "is this safe to execute in a single block without vote?" question. This is the same kind of review one does for a multisig signer list — just applied to the function-call list instead.

**Status / resolution.** **No change required to code or deployment.** The role configuration and GuardCM wiring are correct by design. This section is retained as living documentation so future operators understand the layering instead of flagging a false positive.

## 6. Findings

### 6.1 Summary

| Severity | Count | IDs |
|---|---|---|
| High | 0 | — |
| Medium | 0 | — |
| Low | 1 (carry-over, internal18 Low — **won't-fix**, now in Vulnerabilities_list #8) | `removeNominee` slope drift |
| Notes | 9 (7 carry-over + 1 on-chain observation + 1 new) | see §6.2, §6.3; the second on-chain observation from §5.5 was reclassified as "by design, documentation only" after the GuardCM layering was reviewed |

### 6.2 New finding this pass

#### N-1. `VoteWeighting.removeNominee` — swapped `OwnerOnly` error arguments

`contracts/VoteWeighting.sol` line 590:

```solidity
if (msg.sender != owner) {
    revert OwnerOnly(owner, msg.sender);      // <-- args swapped
}
```

The error is declared line 47 as:

```solidity
/// @param sender Sender address.
/// @param owner  Required sender address as an owner.
error OwnerOnly(address sender, address owner);
```

The two other `revert OwnerOnly(...)` sites in the same file (lines 372, 390) pass `(msg.sender, owner)` — **correct**. Only the `removeNominee` path passes the arguments in reverse order.

**Impact.** Cosmetic / debug-info only. Execution behaviour is unaffected: the `revert` fires for the right condition. But a caller decoding the revert data sees `sender = <Timelock>` / `owner = <caller>`, i.e. the opposite of reality — this will confuse incident-response tooling, Tenderly traces, and anyone reading revert strings from `eth_call` simulations.

**Severity.** Notes (cosmetic). Fix is a one-line swap.

**Status / resolution.** **Will NOT be fixed.** `VoteWeighting` is not upgradeable and a redeploy-for-a-cosmetic bug is not justified — we only redeploy this contract if something absolutely critical forces our hand. The swapped-arg revert path is instead documented in `docs/Vulnerabilities_list_governance.md` (new entry) so any future tooling that decodes `OwnerOnly` revert data from `VoteWeighting` on `removeNominee` is aware the two address fields are reported in reversed order. The revert itself still fires for the correct condition; execution behaviour is unchanged.

### 6.3 Internal18 findings — status on HEAD

All internal18 findings were re-verified against HEAD `76bda389`:

| Internal18 finding | Current status |
|---|---|
| Low — `removeNominee` slope drift (extends Vulnerabilities_list #8) | **Will NOT be fixed** — same reasoning as the N-1 `OwnerOnly` swap: `VoteWeighting` is not upgradeable and we don't redeploy it for non-critical issues. Already captured in `docs/Vulnerabilities_list_governance.md` entry #8 (the slope/`changesSum` drift sub-section was added post-internal18). Operational mitigation (voter cleanup / two-step zero-then-remove) documented there. |
| Notes — FxPortal `setFxRootTunnel`/`setFxChildTunnel` lack access control during deploy window | Risk window closed (tunnel addresses already set); still "redeploy = re-open" |
| Notes — `addNomineeEVM` / `addNomineeNonEVM` permissionless | Confirmed; design choice |
| Notes — `OLAS.mint()` silent no-op when inflation cap hit | Confirmed; documented design |
| Notes — `governorDelay` ↔ `minDelay` circular desync | Confirmed; see also §5.4 for live-state observation |
| Notes — `ProcessBridgedDataWormhole` hardcoded `TIMELOCK` constant | Confirmed; trade-off for compile-time safety |
| Notes — Mixed `pragma` across contracts | Confirmed (OLAS/veOLAS/buOLAS `^0.8.15`, wveOLAS/FxGovernorTunnel/HomeMediator `^0.8.19`, GovernorOLAS `^0.8.20`, BridgeMessenger/OptimismMessenger/WormholeMessenger `^0.8.23`, VoteWeighting `^0.8.25`, Burner `^0.8.28`, everything else `^0.8.30`) |
| Low — `Burner.sol` 0% coverage | **Fixed** — `test/Burner.js` (6 tests) added |
| Notes — C4A fix revert paths untested | **Fixed** — regression tests added in `test/GuardCM.js` |
| Notes — `GovernorOLAS` exceeds 24576-byte limit | Noted; already deployed on mainnet |

**No new manual-review finding from the fresh read beyond N-1 above.** The bridge delegatecall storage-layout contract (GuardCM ↔ ProcessBridgedData* both inherit VerifyData → slot 0 is `mapAllowedTargetSelectorChainIds` in both) remains correctly aligned; I traced inheritance for all 5 verifiers.

## 7. `docs/Vulnerabilities_list_governance.md` hygiene

The document now tracks **11 items** (10 carried forward + 1 added this pass for N-1). All re-verified against HEAD.

| # | Title | Severity | Code still present? | Mitigation in place? |
|---|---|---|---|---|
| 1 | `getPastVotes` wrong for pre-lock blocks | Low | ✅ yes | ✅ wveOLAS wraps |
| 2 | `balanceOfAt` wrong for pre-lock blocks | Low | ✅ yes | ✅ wveOLAS wraps |
| 3 | `_checkpoint` memory-pointer aliasing | Medium | ✅ yes (Curve-derived) | ✅ weekly cron expected |
| 4 | `createLockFor` griefing | Medium | ✅ yes | attacker-funded, buOLAS revoke guardrail |
| 5 | `totalSupplyLockedAtT` | Low | ✅ yes | ✅ wveOLAS wraps |
| 6 | `getPastTotalSupply` reverts on early blocks | Low | ✅ yes | — caller-side discipline |
| 7 | `HomeMediator.processMessageFromForeign` no chainId check | Informative | ✅ yes | Single-chain AMB today |
| 8 | `removeNominee` orphaned voting power (+ slope/`changesSum` drift sub-finding) | Low | ✅ yes | user-side `revokeRemovedNomineeVotingPower`; two-step zero-then-remove workaround |
| 9 | `_addNominee`/`removeNominee` Dispenser sync | Informative | ✅ yes | deploy Dispenser early |
| 10 | `voteForNomineeWeights` lock-expiry edge | Informative | ✅ yes | user extends lock |
| 11 | **`removeNominee` `OwnerOnly` revert-data arg order (NEW — N-1)** | **Informative** | ✅ yes | tooling-side: decode revert as `(owner, sender)` for this call site |

**Hygiene status.**

- Entry #8 now includes the slope / `changesSum` drift sub-finding from internal18 (potential `oldSum - oldWeight` underflow DoS), with full scenario and operational workarounds. No further documentation action required on #8.
- **Entry #11 added in this pass** for the N-1 `OwnerOnly` swapped-args revert in `VoteWeighting.removeNominee`. `VoteWeighting` won't be redeployed for a cosmetic bug, so N-1 is a "deliberately unfixed" trade-off documented for revert-data decoders — exactly the category this document is for.

**Nothing has been removed** from the list — all previously listed items still describe live code paths.

**C4A M-01 is NOT added to this list** because it was a *defect in the verifier*, which is now *fixed*; the file is reserved for known, **deliberately unfixed** trade-offs mitigated elsewhere.

## 8. Conclusion

- **C4A M-01** (the one governance-scope external finding) — **FIXED** and verified on code (§4.1).
- **On-chain owner map (§5)** — all governance contracts resolve to the Timelock; no EOA-owned admin (no Kelp-pattern exposure). CM Safe 5/9 healthy.
- **Deployed vs. repo delta (§5.4)** — the new `governorDelay` field is not yet deployed on the live Governor; when it is, the effective delay goes from 0 s to 43.6 h (setting in `globals_mainnet.json`). **Resolution: new `GovernorOLAS` to be deployed ASAP after this audit round is signed off.** Not a code bug.
- **CM Safe has `PROPOSER_ROLE` + `EXECUTOR_ROLE`** on the Timelock, with `minDelay = 0` (§5.5) — **setup is correct by design.** The real access-control layer for CM is the Gnosis Safe `GuardCM` guard, which restricts every `scheduleBatch` payload to the governance-curated allowlist `mapAllowedTargetSelectorChainIds`. That allowlist can only be expanded by a Governor vote (`setTargetSelectorChainIds` is Timelock-only). Within the allowlist, CM acts unilaterally — providing a sub-minute operational fast path for bridge messages, module pauses, etc., demonstrated live on 2026-01-21 in two mainnet txs. The Governor redeployment (§5.4) does not close this path (and is not meant to); `governorDelay` applies only to Governor-originated proposals. Residual opsec item: periodically review `mapAllowedTargetSelectorChainIds` contents for anything that shouldn't be in a sub-minute CM lane.
- **New code findings this pass:** 1 cosmetic (N-1, `OwnerOnly` args swapped in `removeNominee`). **Resolution: will NOT be fixed in code — added as entry #11 in `Vulnerabilities_list_governance.md`, since `VoteWeighting` is not redeployed for non-critical issues.**
- **Internal18 findings:** all re-verified; Low on Burner coverage and Notes on C4A-fix test gaps are marked Fixed; `removeNominee` slope drift carry-over Low **will NOT be fixed** (same reasoning as N-1 — covered by Vulnerabilities_list entry #8); the rest are unchanged and operationally accepted.
- **`Vulnerabilities_list_governance.md`** — now 11 entries (10 carried forward + #11 newly added for N-1). Entry #8 already extended with the slope/`changesSum` drift sub-finding.

**Verdict: no High / Medium / exploitable-Low findings in the governance repo on commit `76bda389`.** The C4A external audit closed the only serious governance issue (Arbitrum bridge refund drain). All remaining items are either (a) closed by the pending `GovernorOLAS` redeployment, (b) permanent Vulnerabilities-list entries tracking deliberately-unfixed trade-offs in `VoteWeighting`, or (c) well-understood inherited Curve behaviour and operational discipline items.

## 9. Methodology Compliance Report (AGENT-RULES.md)

| Rule | Compliance |
|---|---|
| 1. Exhaustive checking | ✓ C4A (11H+12M+15L) triaged; Vulnerabilities_list (10 entries) all checked; internal18 findings all re-verified |
| 2. Cross-domain patterns | ✓ all applicable DeFi / bridge / governance patterns applied (inherited from internal18, which covered 308 checklist items) |
| 3. Checklist log | ✓ this document + internal18 checklist table (§6.3 in internal18) |
| 4. Playbook updates all-or-nothing | ✓ v2.22 applied; bridge + governance patterns covered |
| 5. Post-audit vulnerability monitoring | ✓ C4A M-01 → fix confirmed; cross-checked with internal18 |
| 6. No premature "all clear" | ✓ §6 lists remaining carry-over findings explicitly |
| 7. Compliance report | ✓ this section |

**Methodology rules followed:**
- C4A verification matrix tabulating every finding (§4). ✓
- On-chain owner map with Kelp-pattern check (§5). ✓
- Vulnerabilities_list hygiene section (§7). ✓
