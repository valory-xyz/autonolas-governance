# Internal audit 19 of autonolas-governance (post-C4A re-audit)

Repository: https://github.com/valory-xyz/autonolas-governance
Commit audited: `76bda389` (Merge PR #192 `address_audit18` → main)
Audit date: 2026-04-21
Deliverable style: internal template (C4A verification matrix + on-chain owner map + Vulnerabilities_list hygiene)
Prior reference: `audits/internal18/README.md`

## 0. C4A 2026-01 findings summary (governance-scope)

The C4A 2026-01 contest covers the whole Olas mono-org (`autonolas-tokenomics`, `autonolas-registries`, `autonolas-governance`). Of the 23 confirmed H + M findings (11H + 12M), exactly **one** lands on a contract in this repository:

| C4A ID | Summary | Code status | Deployment status | Reference |
|---|---|---|---|---|
| **S-629 (= M-01)** | Arbitrum bridge — `ProcessBridgedDataArbitrum.processBridgeData` decoded but did not validate `l2CallValue`, `excessFeeRefundAddress`, `callValueRefundAddress`; a CM-scheduled proposal could redirect L2 refunds/call-value to an attacker | ✅ **Fixed in `origin/main`** | ⚪ **Code fix only — never deployed** (modular `bridge_verifier/*` pattern is brand-new; will land on-chain together with the pending GuardCM / GovernorOLAS redeployment, see §5.4) | [`4fd7d98`](https://github.com/valory-xyz/autonolas-governance/commit/4fd7d9896332c3cc5b00de8d67f402cb70c154f9) — branch `audit_fixes`, PR [#185](https://github.com/valory-xyz/autonolas-governance/pull/185) |

The remaining **22 H + M findings** (11H + 11M) target `autonolas-tokenomics` or `autonolas-registries` and are enumerated row-by-row in **§4 — C4A 2026-01 verification matrix**; the **15 Lows** are disclosed at aggregate level in §4.0.1. Per-finding code status, deployment status (where the responsible repo's snapshot expresses one), and per-repo handoff are recorded in those sections. Details of the S-629 / M-01 fix verification are in §4.1.

**Status vocabulary (used in §4 matrix and elsewhere in this report):**

| Code status | Meaning |
|---|---|
| ✅ Fixed in `origin/main` | Code fix landed on the responsible repo's `origin/main` |
| 🟢 Fixed on feature branch | Code fix landed on a non-`main` feature branch (e.g., `fix_oracle_v2`); not yet merged |
| 🟠 Partially fixed | Some attack paths closed in code, others still live |
| 📝 Documented (known issue) | Not fixed; explicitly accepted on the responsible repo's vulnerabilities-list |
| 🔴 Not fixed (open) | Not fixed in code; not documented as accepted; tracked openly |

| Deployment status | Meaning |
|---|---|
| 🟢 Live on-chain | Code fix is deployed and live on the responsible repo's target chain(s) |
| 🟡 Pending redeploy | Code fix landed; the on-chain version is still the older code; redeployment of an existing contract required to land the fix |
| ⚪ Code fix only — never deployed | Code fix exists; the affected contract has no prior on-chain version (brand-new file or never-shipped contract) |
| — (N/A) | Code is not fixed (not applicable) |
| Not verified here | This report did not verify the on-chain deployment state of the responsible repo's fix — see that repo's handoff |

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

## 4. C4A 2026-01 verification matrix

The C4A 2026-01 report is repo-wide across the Olas mono-org. Every finding was classified by the contract / repository it touches. The full disposition table below makes explicit, per finding, (a) which repo owns the fix, (b) whether it is governance-scope, and (c) the final status — fixed, partially fixed, accepted as a known issue (vulnerabilities-list), or not fixed and tracked in the responsible repo.

### 4.0 Full disposition (High + Medium, n = 23 = 11H + 12M)

Source: filtered C4A status snapshot — an **external/local audit input**, not committed to this repository. Derived from the C4A 2026-01 submissions index ([`code4rena.com/evaluate/j3PRAMM3fVq`](https://code4rena.com/evaluate/j3PRAMM3fVq)) and filtered to `severity = high|medium`, baseline `origin/main` as of 2026-04-10; `fix_oracle_v2` branch noted where applicable for tokenomics. Reproducing the snapshot from scratch requires re-running that filter against the C4A submissions index — the table below preserves every per-row attribute (sev, repo, status, fix-commit link) needed to re-derive it.

The **Code status** column says where in the source tree the fix lives; the **Deployment status** column says whether that fix is live on-chain. The two are independent and used to be conflated in the prior version of this matrix — the conflation is exactly what this split is meant to resolve. Vocabulary is defined in §0.

| C4A ID | Sev | Repo | Gov-scope? | Code status | Deployment status | Reference |
|---|---|---|---|---|---|---|
| [S-229](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-229)   | H | autonolas-registries | No | 🔴 Not fixed (open) | — (N/A) | Tracked in `autonolas-registries` — out of scope for this report |
| [S-248](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-248)   | H | autonolas-tokenomics | No | 🟢 Fixed on `fix_oracle_v2` | Not verified here (branch not merged to `origin/main`) | [`33468a4`](https://github.com/valory-xyz/autonolas-tokenomics/commit/33468a4) |
| [S-347](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-347)   | H | autonolas-tokenomics | No | 🔴 Not fixed (open) | — (N/A) | Tracked in `autonolas-tokenomics` — out of scope for this report |
| [S-471](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-471)   | H | autonolas-tokenomics | No | 🔴 Not fixed (open) | — (N/A) | Tracked in `autonolas-tokenomics` — out of scope for this report |
| [S-578](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-578)   | H | autonolas-registries | No | ✅ Fixed in `origin/main` | Not verified here | [`7674c5c9`](https://github.com/valory-xyz/autonolas-registries/commit/7674c5c9) |
| [S-847](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-847)   | H | autonolas-tokenomics | No | 🟢 Fixed on `fix_oracle_v2` | Not verified here (branch not merged to `origin/main`) | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b) |
| [S-853](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-853)   | H | autonolas-tokenomics | No | 🟢 Fixed on `fix_oracle_v2` | Not verified here (branch not merged to `origin/main`) | [`33468a4`](https://github.com/valory-xyz/autonolas-tokenomics/commit/33468a4) |
| [S-858](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-858)   | H | autonolas-registries | No | 🔴 Not fixed (open) | — (N/A) | Tracked in `autonolas-registries` — out of scope for this report |
| [S-862](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-862)   | H | autonolas-registries | No | 🔴 Not fixed (open) | — (N/A) | Tracked in `autonolas-registries` — out of scope for this report |
| [S-1068](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-1068) | H | autonolas-tokenomics | No | 🟢 Fixed on `fix_oracle_v2` | Not verified here (branch not merged to `origin/main`) | [`33468a4`](https://github.com/valory-xyz/autonolas-tokenomics/commit/33468a4) |
| [S-1187](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-1187) | H | autonolas-registries | No | 🟠 Partially fixed | Not verified here | [`7674c5c9`](https://github.com/valory-xyz/autonolas-registries/commit/7674c5c9) — ServiceManager guarded; StakingBase paths unchanged |
| [S-256](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-256)   | M | autonolas-tokenomics | No | 🟢 Fixed on `fix_oracle_v2` | Not verified here (branch not merged to `origin/main`) | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b) |
| **[S-629](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-629) (= M-01)** | **M** | **autonolas-governance** | **✅ Yes** | **✅ Fixed in `origin/main`** | **⚪ Code fix only — never deployed** (new modular `bridge_verifier/*` contracts, including `ProcessBridgedDataArbitrum`, are not in `globals_mainnet.json`; `deploy_26_03_*` script has not been run on mainnet yet — bundled with pending GuardCM / GovernorOLAS deployment, §5.4) | this repo: [`4fd7d98`](https://github.com/valory-xyz/autonolas-governance/commit/4fd7d9896332c3cc5b00de8d67f402cb70c154f9), PR [#185](https://github.com/valory-xyz/autonolas-governance/pull/185); code-level verification in §4.1 |
| [S-668](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-668)   | M | autonolas-tokenomics | No | 🔴 Not fixed (open) | — (N/A) | Tracked in `autonolas-tokenomics` — out of scope for this report |
| [S-763](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-763)   | M | autonolas-registries | No | 🔴 Not fixed (open) | — (N/A) | Tracked in `autonolas-registries` — out of scope for this report |
| [S-885](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-885)   | M | autonolas-registries | No | 🔴 Not fixed (open) | — (N/A) | Tracked in `autonolas-registries` — out of scope for this report |
| [S-1030](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-1030) | M | autonolas-tokenomics | No | 📝 Documented (known issue) | — (N/A) | Listed in `autonolas-tokenomics` vulnerabilities-list (S-1030) |
| [S-1045](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-1045) | M | autonolas-tokenomics | No | 🟢 Fixed on `fix_oracle_v2` | Not verified here (branch not merged to `origin/main`) | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b) |
| [S-1052](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-1052) | M | autonolas-tokenomics | No | 🟢 Fixed on `fix_oracle_v2` | Not verified here (branch not merged to `origin/main`) | [`33468a4`](https://github.com/valory-xyz/autonolas-tokenomics/commit/33468a4) |
| [S-1110](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-1110) | M | autonolas-tokenomics | No | 🟢 Fixed on `fix_oracle_v2` | Not verified here (branch not merged to `origin/main`) | [`ca9203a`](https://github.com/valory-xyz/autonolas-tokenomics/commit/ca9203a) |
| [S-1231](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-1231) | M | autonolas-tokenomics | No | 🟢 Fixed on `fix_oracle_v2` | Not verified here (branch not merged to `origin/main`) | [`ca9203a`](https://github.com/valory-xyz/autonolas-tokenomics/commit/ca9203a) |
| [S-1266](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-1266) | M | autonolas-tokenomics | No | 🟢 Fixed on `fix_oracle_v2` | Not verified here (branch not merged to `origin/main`) | [`0948e8b`](https://github.com/valory-xyz/autonolas-tokenomics/commit/0948e8b) |
| [S-1279](https://code4rena.com/evaluate/j3PRAMM3fVq/submissions/S-1279) | M | autonolas-tokenomics | No | 🟢 Fixed on `fix_oracle_v2` | Not verified here (branch not merged to `origin/main`) | [`33468a4`](https://github.com/valory-xyz/autonolas-tokenomics/commit/33468a4) |

**Per-repo split (H + M) by code status:**

| Repo | Total | ✅ Fixed in `origin/main` | 🟢 Fixed on feature branch | 🟠 Partially fixed | 📝 Documented | 🔴 Not fixed |
|---|---|---|---|---|---|---|
| autonolas-governance | **1** | **1 (S-629 / M-01)** | 0 | 0 | 0 | 0 |
| autonolas-registries | 7 | 1 (S-578) | 0 | 1 (S-1187) | 0 | 5 (S-229, S-858, S-862, S-763, S-885) |
| autonolas-tokenomics | 15 | 0 | 11 | 0 | 1 (S-1030) | 3 (S-347, S-471, S-668) |
| **Total** | **23** | **2** | **11** | **1** | **1** | **8** |

**Per-repo split (H + M) by deployment status — only what this report verified:**

| Repo | Verified deployment status | Notes |
|---|---|---|
| autonolas-governance | ⚪ Code fix — never deployed (1 of 1) | S-629 fix lives in code; the new modular `bridge_verifier/*` contracts are not in `globals_mainnet.json` and `deploy_26_03_*` has not been run on mainnet yet. Bundled with pending GuardCM / GovernorOLAS deployment (§5.4). |
| autonolas-registries | Not verified here (7 of 7) | Deployment of `origin/main` registries fixes is not in scope for this report. See `autonolas-registries` audit handoff. |
| autonolas-tokenomics | Not verified here (15 of 15) | Of these, 11 fixes are on `fix_oracle_v2` which **is not merged to `origin/main`** as of 2026-04-10 — so those 11 are at least *Pending merge* before they could be considered for deployment. See `autonolas-tokenomics` audit handoff. |

**Key disposition for governance-scope:** the only governance-scope finding is **S-629 (= M-01)**: code is **fixed in `origin/main`**; on-chain status is **code fix only — never deployed**. Code-level fix verification in §4.1; deployment-state verification in §5.4 (the same pending redeploy that closes the `governorDelay`/`minDelay` gap closes the M-01 fix's deployment gap, in a single coordinated rollout).

**All other 22 H + M findings (11H + 11M) target `autonolas-tokenomics` or `autonolas-registries`.** Their code-level disposition is shown above; their on-chain liveness is **not verified by this report** and is the responsibility of those two repos' audit handoffs and vulnerabilities-list documents. None of them touch any contract in `autonolas-governance` — verified by repo classification on the C4A submission and confirmed by reading the corresponding source files.

### 4.0.1 Lows (n = 15) — disposition

The 15 Low findings from the C4A 2026-01 report were **not individually enumerated** in the filtered status snapshot used as input here (the external/local snapshot referenced in §4.0 was filtered to `severity = high|medium` for the H/M handoff round). Per the per-submission repo classification we ran during C4A triage, **none of the 15 Lows landed on a governance-repo contract** — they cluster in `autonolas-tokenomics` (oracle / liquidity-manager paths) and `autonolas-registries` (staking / service-manager paths), and are tracked under those repos' Low-severity handoffs.

**Honest gap-disclosure:** if a future hygiene pass requires per-ID rows for the 15 Lows in this matrix (with S-IDs, summaries, and current statuses), the C4A submissions index for the 2026-01 contest ([`code4rena.com/evaluate/j3PRAMM3fVq`](https://code4rena.com/evaluate/j3PRAMM3fVq)) is the source of truth and the snapshot would need to be re-imported with the severity filter relaxed. The aggregate claim "0 Lows are governance-scope" stands on the repo classification we performed; the per-row enumeration does not appear in this document because it never entered the input snapshot we worked from.

**Disposition summary (Lows):** 0 governance-scope, 15 tracked in `autonolas-tokenomics` / `autonolas-registries` (per-ID details in those repos' audit handoffs).

### 4.0.2 What this matrix does and does not assert

To make the scope of this report explicit (so the disposition matrix is not over-read):

- **Asserted in this document:** for the **1** governance-scope finding (S-629 / M-01), both the **code-level fix** (§4.1, on commit `76bda389`) and the **deployment status** (§5.4, on `globals_mainnet.json` 2026-04-21 / `deploy_26_03_*` not yet run) are verified by this report. For the **22** out-of-scope H + M findings (and the **15** Lows), this document only records what we observed in the filtered C4A status snapshot — namely the responsible repo and the snapshot's stated **code-level** status.
- **Not asserted in this document:** we have **not** performed code-level fix verification, and have **not** performed any deployment / on-chain verification, for the tokenomics or registries findings — that work belongs in those repos' audit handoffs and is out of scope here. Where a row says "Fixed on `fix_oracle_v2`" or "Fixed in `origin/main`" for those two repos, that reflects the C4A snapshot at 2026-04-10, not a re-verification on the current `HEAD` of those repos and not an on-chain check. The deployment column for those rows says **"Not verified here"** to make this honest.
- **The "Code status" and "Deployment status" columns are independent.** A finding can be code-fixed and not yet live (the case for S-629 / M-01 — the modular `bridge_verifier/*` pattern has never been deployed to mainnet); or code-fixed and live (the typical case once a redeploy happens); or accepted as a known issue with no code change at all. Conflating these two dimensions into a single "FIXED / NOT FIXED" status is exactly what the prior matrix version did and what this split is meant to fix.
- **No C4A finding is silently dropped.** Every H + M ID appears in the matrix above, classified into governance-scope vs. out-of-scope, with an explicit code status, a deployment status (or "Not verified here"), and, where applicable, a fix-commit link. The 15 Lows are explicitly disclosed at aggregate level with the gap noted.

### 4.1 C4A M-01 — Arbitrum bridge unchecked refund / value

**Original C4A finding.** `ProcessBridgedDataArbitrum.processBridgeData` decoded the Arbitrum retryable-ticket parameters (`l2CallValue`, `excessFeeRefundAddress`, `callValueRefundAddress`) but **did not validate them**. A CM-scheduled proposal could set `callValueRefundAddress` to an attacker address and, if `l2CallValue > 0`, the L2 would refund the non-executed call value to the attacker (or route excess fee refund to an attacker). The scenario drains ETH/refunds from the Timelock's L2 bridge escrow.

**Fix branch:** [`audit_fixes`](https://github.com/valory-xyz/autonolas-governance/tree/audit_fixes) → PR [#185](https://github.com/valory-xyz/autonolas-governance/pull/185), fix commit [`4fd7d98`](https://github.com/valory-xyz/autonolas-governance/commit/4fd7d9896332c3cc5b00de8d67f402cb70c154f9) (`refactor: addressing GuardCM found issues`).

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

✅ **C4A M-01 — code fix verified at the source level.** ⚪ **Not yet deployed to mainnet** — the new modular `bridge_verifier/*` contracts (including `ProcessBridgedDataArbitrum`) are absent from `globals_mainnet.json`, and `deploy_26_03_process_bridged_data_arbitrum.sh` has not been run; the fix lands on-chain together with the pending GuardCM / GovernorOLAS deployment described in §5.4. **No governance-scope C4A finding remains open in source code.** The deployment-side closure is gated on the same audit sign-off + redeploy that closes §5.4's `governorDelay` / `minDelay` gap.

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
| Notes — `addNomineeEVM` / `addNomineeNonEVM` permissionless | Confirmed; design choice. **Migrated this pass to Vulnerabilities_list entry #14** with the off-chain spam-filter / monitoring guidance and a documented optional code-level cap as a future redeploy lever. |
| Notes — `OLAS.mint()` silent no-op when inflation cap hit | Confirmed; documented design. **Migrated this pass to Vulnerabilities_list entry #12** for integrator-facing mitigation guidance. |
| Notes — `governorDelay` ↔ `minDelay` circular desync | Confirmed; see also §5.4 for live-state observation. **Migrated this pass to Vulnerabilities_list entry #13** with documented CM-fast-path break-glass recovery. |
| Notes — `ProcessBridgedDataWormhole` hardcoded `TIMELOCK` constant | Confirmed; trade-off for compile-time safety. **Migrated this pass to Vulnerabilities_list entry #15** (redeploy-coupling rule for any future Timelock migration; suggested follow-up to parameterise on next bridge_verifier redeploy). |
| Notes — Mixed `pragma` across contracts | Confirmed (OLAS/veOLAS/buOLAS `^0.8.15`, wveOLAS/FxGovernorTunnel/HomeMediator `^0.8.19`, GovernorOLAS `^0.8.20`, BridgeMessenger/OptimismMessenger/WormholeMessenger `^0.8.23`, VoteWeighting `^0.8.25`, Burner `^0.8.28`, everything else `^0.8.30`) |
| Low — `Burner.sol` 0% coverage | **Fixed** — `test/Burner.js` (6 tests) added |
| Notes — C4A fix revert paths untested | **Fixed** — regression tests added in `test/GuardCM.js` |
| Notes — `GovernorOLAS` exceeds 24576-byte limit | **Fixed in this pass** — reduced `optimizer_runs` from `1,000,000` to `200` in both `foundry.toml` and `hardhat.config.js`. `GovernorOLAS` deployed bytecode goes from **24,936 → 20,479 bytes** (4,097-byte EIP-170 margin). All other governance contracts continue to compile cleanly under the new setting. The contract is now portable to chains that strictly enforce EIP-170. **Treated as a config fix, not a `Vulnerabilities_list_governance.md` entry**, because it is fully resolved at the source-tree level (the next deployment will pick up the new bytecode automatically). Going forward, the EIP-170 size budget is a hard rule — see the per-user memory entry for the flagging policy. |

**No new manual-review finding from the fresh read beyond N-1 above.** The bridge delegatecall storage-layout contract (GuardCM ↔ ProcessBridgedData* both inherit VerifyData → slot 0 is `mapAllowedTargetSelectorChainIds` in both) remains correctly aligned; I traced inheritance for all 5 verifiers.

## 7. `docs/Vulnerabilities_list_governance.md` hygiene

The document now tracks **15 items** (10 carried forward + 5 added this pass: N-1 OwnerOnly swap, OLAS.mint silent no-op, governorDelay/minDelay desync, addNominee permissionless, ProcessBridgedDataWormhole hardcoded TIMELOCK). All re-verified against HEAD.

**Note on the `GovernorOLAS` 24,576-byte size finding (internal18 Note):** this one is **NOT** added to the vulnerabilities list — it has been **fixed at the compiler-config level** by reducing `optimizer_runs` from `1,000,000` to `200` in both `foundry.toml` and `hardhat.config.js`. New `GovernorOLAS` deployed bytecode size: **20,479 bytes** (4,097-byte EIP-170 margin). The next deployment of `GovernorOLAS` (§5.4) picks up this smaller bytecode automatically. Going forward, **any contract being modified or queued for deployment must stay under the 24,576-byte EIP-170 limit, and a violation is flagged immediately** — captured as a durable rule in agent memory rather than a vulnerability.

> **Disambiguation — the 5 entries added this pass are NOT unresolved C4A 2026-01 findings.** Per §4, the only governance-scope C4A finding is **S-629 / M-01**, and it is **fixed** on `origin/main` (verified at code level in §4.1). It is therefore deliberately **not** added to `Vulnerabilities_list_governance.md` (which is reserved for *deliberately-unfixed* trade-offs). The five new entries below come from the **internal review track**:
>
> - **#11 — `OwnerOnly` revert-data arg order:** finding **N-1**, originated in this internal19 pass (§6.2). Cosmetic-only, will not be fixed (no redeploy of `VoteWeighting` for non-critical issues).
> - **#12 — `OLAS.mint` silent no-op on inflation cap:** carry-over from **internal18 Notes**, migrated into the formal vulnerabilities-list this pass for integrator-facing mitigation guidance (§6.3 row).
> - **#13 — `governorDelay` ↔ `minDelay` desync:** carry-over from **internal18 Notes**, migrated into the formal vulnerabilities-list this pass with the documented CM-fast-path break-glass recovery (§6.3 row, see also §5.4).
> - **#14 — `addNomineeEVM` / `addNomineeNonEVM` permissionless:** carry-over from **internal18 Notes**, migrated this pass with off-chain spam-filter / monitoring guidance and an optional code-level cap as a future redeploy lever.
> - **#15 — `ProcessBridgedDataWormhole` hardcoded `TIMELOCK` constant:** carry-over from **internal18 Notes**, migrated this pass with the redeploy-coupling rule (Timelock redeploy ⇒ Wormhole verifier redeploy) and a suggested parameterisation follow-up bundled with the next bridge_verifier redeploy.
>
> Separately, the **`GovernorOLAS` 24,576-byte size note (internal18)** was **fixed at the compiler-config level** in this pass (`optimizer_runs` 1M → 200) and is therefore **not** in the vulnerabilities list — see the §6.3 row.
>
> No C4A 2026-01 finding — H, M, or L — is recorded in `Vulnerabilities_list_governance.md` as "accepted" or "known issue" by this pass, because no C4A 2026-01 finding has that disposition for the governance repo (the single governance-scope item, S-629 / M-01, was fixed in code).

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
| 12 | **OLAS `mint` silent no-op on inflation cap (NEW — migrated from internal18)** | **Informative** | ✅ yes | integrators: pre-check `inflationControl`/`inflationRemainder` or verify balance delta, do not assume revert-on-failure |
| 13 | **`governorDelay` vs timelock `minDelay` desync (NEW — migrated from internal18)** | **Informative** | ✅ yes | always update `minDelay` and `governorDelay` in same proposal; CM fast-path `updateDelay` is break-glass recovery |
| 14 | **`addNomineeEVM`/`addNomineeNonEVM` permissionless (NEW — migrated from internal18)** | **Informative** | ✅ yes | UI spam filter + off-chain `AddNomineeHash` rate alerts; owner-side periodic cleanup; optional code-level cap on `setNominees.length` as a future redeploy lever |
| 15 | **`ProcessBridgedDataWormhole` hardcoded `TIMELOCK` (NEW — migrated from internal18)** | **Informative** | ✅ yes | Timelock-redeploy runbook must redeploy + re-wire Wormhole verifier; consider parameterising on the next bridge_verifier redeploy |

**Hygiene status.**

- Entry #8 includes the slope / `changesSum` drift sub-finding from internal18 (potential `oldSum - oldWeight` underflow DoS), with full scenario and operational workarounds.
- **Entry #11 added in this pass** for the N-1 `OwnerOnly` swapped-args revert in `VoteWeighting.removeNominee`.
- **Entries #12 and #13 added in this pass** — migrated from the internal18 "Notes" section into the formal list, since both are deliberately-unfixed trade-offs with live operational implications (integrator misuse for #12, governance bricking recovery for #13).
- **Entries #14 and #15 added in this pass** — also migrated from internal18 "Notes": #14 captures the permissionless `addNominee*` griefing surface and the recommended off-chain-only mitigation pattern; #15 captures the Wormhole-verifier ↔ Timelock redeploy-coupling rule. With these two additions the doc now covers every internal18 deliberately-unfixed Note that has operational/security implications. Internal18 Notes that did **not** make the list are: mixed pragma versions (style only), and `GovernorOLAS` ≥ 24,576 bytes (resolved at compiler-config level this pass, see §6.3 row + the EIP-170 size-budget rule captured in agent memory).

**Nothing has been removed** from the list — all previously listed items still describe live code paths.

**C4A M-01 is NOT added to this list** because it was a *defect in the verifier*, which is now *fixed*; the file is reserved for known, **deliberately unfixed** trade-offs mitigated elsewhere.

## 8. Conclusion

- **C4A 2026-01 disposition (§4)** — full per-finding matrix recorded for all **23 H + M** items (11H + 12M); **15 Lows** disclosed at aggregate level with the gap noted. The matrix uses two orthogonal status columns — **Code** (fixed in main / fixed on feature branch / partial / documented / not fixed) and **Deployment** (live on-chain / pending redeploy / never deployed / N/A / not verified here) — to avoid conflating "fix exists in source" with "fix is on-chain". Of the 23 H + M, exactly **1 is governance-scope**: **S-629 / M-01** (Arbitrum bridge refund/value verification): **Code = ✅ Fixed in `origin/main`** (commit [`4fd7d98`](https://github.com/valory-xyz/autonolas-governance/commit/4fd7d9896332c3cc5b00de8d67f402cb70c154f9), code-level verification in §4.1); **Deployment = ⚪ Code fix only — never deployed** (modular `bridge_verifier/*` contracts not in `globals_mainnet.json`, bundled with pending GuardCM / GovernorOLAS deployment in §5.4). The other 22 H + M and all 15 Lows target `autonolas-tokenomics` or `autonolas-registries` and are tracked in those repos' audit handoffs; none are governance-scope. **No C4A 2026-01 finding is added to `Vulnerabilities_list_governance.md`** (the file is reserved for governance-repo deliberately-unfixed trade-offs, and S-629 / M-01 was fixed in code).
- **On-chain owner map (§5)** — all governance contracts resolve to the Timelock; no EOA-owned admin (no Kelp-pattern exposure). CM Safe 5/9 healthy.
- **Deployed vs. repo delta (§5.4)** — the new `governorDelay` field is not yet deployed on the live Governor; when it is, the effective delay goes from 0 s to 43.6 h (setting in `globals_mainnet.json`). **Resolution: new `GovernorOLAS` to be deployed ASAP after this audit round is signed off.** Not a code bug.
- **CM Safe has `PROPOSER_ROLE` + `EXECUTOR_ROLE`** on the Timelock, with `minDelay = 0` (§5.5) — **setup is correct by design.** The real access-control layer for CM is the Gnosis Safe `GuardCM` guard, which restricts every `scheduleBatch` payload to the governance-curated allowlist `mapAllowedTargetSelectorChainIds`. That allowlist can only be expanded by a Governor vote (`setTargetSelectorChainIds` is Timelock-only). Within the allowlist, CM acts unilaterally — providing a sub-minute operational fast path for bridge messages, module pauses, etc., demonstrated live on 2026-01-21 in two mainnet txs. The Governor redeployment (§5.4) does not close this path (and is not meant to); `governorDelay` applies only to Governor-originated proposals. Residual opsec item: periodically review `mapAllowedTargetSelectorChainIds` contents for anything that shouldn't be in a sub-minute CM lane.
- **New code findings this pass:** 1 cosmetic (N-1, `OwnerOnly` args swapped in `removeNominee`). **Resolution: will NOT be fixed in code — added as entry #11 in `Vulnerabilities_list_governance.md`, since `VoteWeighting` is not redeployed for non-critical issues.**
- **Internal18 findings:** all re-verified; Low on Burner coverage and Notes on C4A-fix test gaps are marked Fixed; `removeNominee` slope drift carry-over Low **will NOT be fixed** (same reasoning as N-1 — covered by Vulnerabilities_list entry #8); the rest are unchanged and operationally accepted.
- **`Vulnerabilities_list_governance.md`** — now 15 entries (10 carried forward + #11 N-1 OwnerOnly + #12 OLAS.mint silent no-op + #13 governorDelay/minDelay desync + #14 addNominee permissionless + #15 ProcessBridgedDataWormhole hardcoded TIMELOCK). Entry #8 already extended with the slope/`changesSum` drift sub-finding. Entries #12–#15 migrated from internal18 "Notes" so the formal doc now covers every deliberately-unfixed governance-repo trade-off with operational mitigations. **None of the 5 newly added entries are C4A 2026-01 findings** — they are internal-review findings (one originated in this pass, four carried over from internal18). See §7 disambiguation note.
- **EIP-170 size budget** — internal18's `GovernorOLAS > 24,576 bytes` Note is **fixed at the compiler-config level** this pass: `optimizer_runs` reduced from `1,000,000` to `200` in both `foundry.toml` and `hardhat.config.js`; `GovernorOLAS` deployed bytecode goes from 24,936 → **20,479 bytes** (4,097-byte EIP-170 margin). Going forward, **any contract being modified or queued for deployment must stay under 24,576 bytes, with violations flagged immediately** — captured as a durable agent-memory rule.

**Verdict: no High / Medium / exploitable-Low findings in the governance repo on commit `76bda389`.** The C4A external audit identified one governance-scope issue (Arbitrum bridge refund drain) and **the fix is in `origin/main`**; the **on-chain closure** of that finding lands together with the pending GuardCM / GovernorOLAS deployment (§5.4) — they are bundled because the new modular `bridge_verifier/*` contracts are wired in via the new GuardCM. All remaining items are either (a) closed by the pending governance redeployment (covering both the M-01 fix's deployment and the `governorDelay`/`minDelay` gap), (b) permanent Vulnerabilities-list entries tracking deliberately-unfixed trade-offs in `VoteWeighting`, or (c) well-understood inherited Curve behaviour and operational discipline items.

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
