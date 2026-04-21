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

The C4A 2026-01 report covers **all** Olas repos (tokenomics, governance, registries). I classified every finding by the contract it touches:

| C4A ID | Title | Target repo | Governance-scope? |
|---|---|---|---|
| H-01..H-04, H-08, H-11 | Tokenomics / Depository / Treasury / Donator / Dispenser | autonolas-tokenomics | ❌ (not governance) |
| H-05, H-06, H-07, H-09, H-10 | Service / Registry logic | autonolas-registries | ❌ (not governance) |
| **M-01** | **Arbitrum bridge — unchecked `l2CallValue` / refund addresses in `ProcessBridgedDataArbitrum`** | **autonolas-governance** | ✅ **YES** |
| M-02..M-07, M-09, M-11, M-12 | Tokenomics / Donator / Dispenser | autonolas-tokenomics | ❌ |
| M-08, M-10 | Service Registry | autonolas-registries | ❌ |
| L-01..L-15 | Oracle / bonding / tokenomics | autonolas-tokenomics | ❌ |
| Disclosures | (various) | — | none governance-scope |

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

RPC: QuikNode mainnet. Addresses sourced from `scripts/deployment/globals_mainnet.json`.

### 5.1 Governance contract owners

| Contract | Address | `owner()` / admin | Verdict |
|---|---|---|---|
| Timelock (`TimelockController`) | `0x3C1f…95fE` | Self-administered + Governor as admin | ✓ |
| GovernorOLAS | `0x8E84…B401` | Token: `wveOLAS` ✓; Timelock: `0x3C1f…95fE` ✓ | ✓ |
| OLAS | `0x0001…5CB0` | owner = Timelock ✓; minter = Treasury `0xa0DA…0f82` ✓ | ✓ |
| veOLAS | `0x7e01…B7b3` | Ownerless (per design) | ✓ |
| wveOLAS | `0x4039…4B40` | Ownerless view wrapper | ✓ |
| buOLAS | `0xb09C…1f73` | owner = Timelock ✓ | ✓ |
| VoteWeighting | `0x9541…c5c1` | owner = Timelock ✓ | ✓ |
| GuardCM | `0x7bB7…6f3a` | owner = Timelock ✓; multisig = CM Safe `0x04C0…2570` ✓; governor = GovernorOLAS ✓ | ✓ |
| Treasury (cross-ref) | `0xa0DA…0f82` | owner = Timelock ✓ | ✓ |

All admin roles for governance contracts trace back to the Timelock multisig. No EOA-owned contracts, no Kelp-pattern `$294M` single-key situation in the governance repo.

### 5.2 Timelock roles (OpenZeppelin v4.6 TimelockController)

| Role | keccak256 | Held by | Verdict |
|---|---|---|---|
| `TIMELOCK_ADMIN_ROLE` | `0x5f58…6ca5` | Timelock self, GovernorOLAS | ✓ (self + governance) |
| `PROPOSER_ROLE` | `0xb09a…9cc1` | GovernorOLAS, **CM Safe** | ⚠ CM has direct scheduling rights — see §5.4 |
| `EXECUTOR_ROLE` | `0xd8aa…9e63` | GovernorOLAS only (not open `address(0)`) | ✓ |
| `CANCELLER_ROLE` | `0xfd64…f783` | GovernorOLAS only (not CM, not Valory) | ✓ |

### 5.3 Multisig composition

| Safe | Threshold | Owners | Kelp-pattern flag |
|---|---|---|---|
| CM Safe (`0x04C0…2570`) | **5 / 9** | 9 EOAs | ✓ healthy — 5-of-9 survives 4 lost keys |
| Valory multisig (`0x87cc…f941`) | **2 / 3** | 3 EOAs | ⚠ 2-of-3 is the minimum acceptable for a treasury-tier Safe; worth flagging only because two keys compromised ⇒ full control |

The CM Safe 5/9 is unchanged from prior audits. The Valory 2/3 is used for OLAS holding / side operations and is not in the governance admin chain.

### 5.4 Deployed vs. repo code — `governorDelay` not yet deployed

**Deployed Governor** (`0x8E84…B401`) fingerprinted via `cast call`:

- `name() = "Governor OLAS"`, `version() = "1"` ✓
- `votingDelay() = 13091 blocks` (~1.8 days), `votingPeriod() = 19636 blocks` (~2.7 days) ✓
- **`governorDelay()` → execution reverted** (selector `0x3a23ed5f`).
- Timelock `getMinDelay() = 0`.

⇒ The deployed Governor is the **OZ v4.x stock `GovernorTimelockControl`** — it does **not** have the new custom `governorDelay` field introduced by `contracts/utils/GovernorTimelockControl.sol`. Because `minDelay = 0`, the "timelock pause" on the deployed contract is 0 seconds; the effective delay between "vote passes" and "execute" is bounded only by the `delay` argument passed to `scheduleBatch` — which OZ stock reads from `_timelock.getMinDelay()`, not from a stored governor-side value.

Practical effect today: vote (3h delay + 2.7d voting) → execute immediately. This has been the live situation since governorTwo was deployed and is not a regression introduced by this PR; flagging it so the deployment of the re-audited code closes it.

**When the code in this repo is redeployed**, the custom `GovernorTimelockControl` (this repo lines 115–122) will pass `delay = governorDelay` to `_timelock.scheduleBatch`, and the constructor enforces `governorDelay ≥ minDelay`. `globals_mainnet.json` sets `governorDelay = 157092` (43.6 h). After deployment the effective timelock will be **≥ 43.6 h** — which is the intended design.

**Action (OpSec):** ensure the Governor redeployment replaces the Timelock's `proposer`/`executor`/`canceller` role-holder, or updates `updateTimelock`/role grants correctly; the role changeover itself must go through the old Governor (which means it is bounded by the 0-second delay — acceptable for a one-time admin transition).

### 5.5 Unusual: CM Safe has `PROPOSER_ROLE`

Direct RPC confirms **CM Safe holds `PROPOSER_ROLE`** on the Timelock. This is not an internal18 finding; it is visible on-chain only. Impact analysis:

- CM Safe can call `Timelock.scheduleBatch(...)` directly, **bypassing** a governance vote. The scheduled operation is queued in the Timelock.
- CM Safe does **not** have `EXECUTOR_ROLE` and the executor is not open (`hasRole(executor, 0x0) == false`), so only GovernorOLAS can execute — and GovernorOLAS only calls `executeBatch` from inside its own `_execute` path, which requires an internal `ProposalState.Queued`. A Timelock-queued batch that has **no matching Governor proposalId** can therefore never be executed via Governor.
- **However**, with `minDelay = 0` (deployed state), a CM-scheduled batch reaches `isOperationReady = true` immediately. If any Safe path could also reach `Timelock.executeBatch` (e.g., future admin grant of executor to CM), it becomes instantly executable. Today this does not happen.
- CM Safe also does **not** have `CANCELLER_ROLE`, so CM cannot cancel Governor-scheduled ops either.

**Severity:** Notes. The live attack surface is zero as long as `EXECUTOR_ROLE` stays restricted to GovernorOLAS. Flagging so the operations team does not accidentally grant `EXECUTOR_ROLE` to CM.

## 6. Findings

### 6.1 Summary

| Severity | Count | IDs |
|---|---|---|
| High | 0 | — |
| Medium | 0 | — |
| Low | 1 (carry-over, internal18 Low) | `removeNominee` slope drift |
| Notes | 7 (6 carry-over + 2 on-chain + 1 new) | see §6.3 |

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

### 6.3 Internal18 findings — status on HEAD

All internal18 findings were re-verified against HEAD `76bda389`:

| Internal18 finding | Current status |
|---|---|
| Low — `removeNominee` slope drift (extends Vulnerabilities_list #8) | Still open (contract not upgradeable; operational workaround is the mitigation) |
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

The document currently tracks 10 items (unchanged since 2024). I re-verified each against HEAD.

| # | Title | Severity | Code still present? | Mitigation in place? |
|---|---|---|---|---|
| 1 | `getPastVotes` wrong for pre-lock blocks | Low | ✅ yes | ✅ wveOLAS wraps |
| 2 | `balanceOfAt` wrong for pre-lock blocks | Low | ✅ yes | ✅ wveOLAS wraps |
| 3 | `_checkpoint` memory-pointer aliasing | Medium | ✅ yes (Curve-derived) | ✅ weekly cron expected |
| 4 | `createLockFor` griefing | Medium | ✅ yes | attacker-funded, buOLAS revoke guardrail |
| 5 | `totalSupplyLockedAtT` | Low | ✅ yes | ✅ wveOLAS wraps |
| 6 | `getPastTotalSupply` reverts on early blocks | Low | ✅ yes | — caller-side discipline |
| 7 | `HomeMediator.processMessageFromForeign` no chainId check | Informative | ✅ yes | Single-chain AMB today |
| 8 | `removeNominee` orphaned voting power | Low | ✅ yes | user-side `revokeRemovedNomineeVotingPower` |
| 9 | `_addNominee`/`removeNominee` Dispenser sync | Informative | ✅ yes | deploy Dispenser early |
| 10 | `voteForNomineeWeights` lock-expiry edge | Informative | ✅ yes | user extends lock |

**Hygiene recommendation.** Consider extending entry #8 with the slope / `changesSum` drift sub-finding from internal18 — right now the PDF only documents "orphaned voting power" but not the potential `oldSum - oldWeight` underflow. This is a minor documentation gap, not a code finding.

**Nothing needs to be removed** from the list — all 10 items still describe live code paths.

**C4A M-01 is NOT added to this list** because it was a *defect in the verifier*, which is now *fixed*; the file is reserved for known, **deliberately unfixed** trade-offs mitigated elsewhere. (Same rule was applied in internal15/tokenomics.)

## 8. Conclusion

- **C4A M-01** (the one governance-scope external finding) — **FIXED** and verified on code (§4.1).
- **On-chain owner map (§5)** — all governance contracts resolve to the Timelock; no EOA-owned admin (no Kelp-pattern exposure). CM Safe 5/9 healthy.
- **Deployed vs. repo delta (§5.4)** — the new `governorDelay` field is not yet deployed on the live Governor; when it is, the effective delay goes from 0 s to 43.6 h (setting in `globals_mainnet.json`). This is a deployment-ordering note, not a code bug.
- **CM Safe has `PROPOSER_ROLE`** on the Timelock (§5.5) — unusual but not exploitable today because `EXECUTOR_ROLE` is restricted to GovernorOLAS.
- **New code findings this pass:** 1 cosmetic (N-1, `OwnerOnly` args swapped in `removeNominee`).
- **Internal18 findings:** all re-verified; Low on Burner coverage and Notes on C4A-fix test gaps are marked Fixed; the rest are unchanged and operationally accepted.
- **`Vulnerabilities_list_governance.md`** — all 10 entries still valid; no removal; optional documentation extension for #8.

**Verdict: no High / Medium / exploitable-Low findings in the governance repo on commit `76bda389`.** The C4A external audit closed the only serious governance issue (Arbitrum bridge refund drain). The remaining surface is well-understood inherited Curve behaviour and operational discipline items.

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
