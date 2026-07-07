# Audit Summary — autonolas-governance internal18

**Date**: 2026-03-17
**Scope**: Full project audit of https://github.com/valory-xyz/autonolas-governance (main branch, commit `bae8da6`)
**Methodology**: Playbook v2.17 + autonolas-internal-audit-methodology
**Contracts**: 27 contracts, ~5142 LOC

## Results

| Severity | Count |
|----------|:-----:|
| High | 0 |
| Medium | 0 |
| Low | 2 |
| Notes/Discussion | 7 |

### Low: VoteWeighting removeNominee slope drift + potential DoS

Extends known vulnerability PDF #8 (which only documents orphaned voting power). When a nominee is removed, its slope is NOT zeroed in `pointsSum`, and `changesSum` entries from voters are NOT cleaned up. Over time, phantom slopes drain the sum to zero via `_getSum()` floor guard. Then `removeNominee` for another nominee reverts on line 611 (`oldSum - oldWeight` underflow — raw subtraction, not `_maxAndSub`). This is custom Olas code — Curve's GaugeController has NO kill_gauge.

**Practical feasibility**: LOW. Requires governance-initiated removal (rare), passive voters not calling `revokeRemovedNomineeVotingPower` (moderate — voters have incentive to reclaim power), multi-year timeframe for phantom slopes to drain sum, and another removal attempt when sum < target weight. Active voting continuously replenishes the sum.

**Additional observation**: `_getSum()` line 237 (`pt.slope -= dSlope`) is also unprotected — in Curve's original Vyper 0.2 this silently wraps, but in Solidity 0.8 it reverts. Same `_maxAndSub` pattern should apply.

**Workaround (no redeployment needed)**: Contract is not upgradeable, but operational mitigations exist:
1. **Voter cleanup before removal**: Before each `removeNominee`, identify unrevoked voters of previously-removed nominees and ensure they call `revokeRemovedNomineeVotingPower()` BEFORE their locks expire (after expiry, changesSum damage is permanent).
2. **Two-step removal**: First have all voters set weight=0 via `voteForNomineeWeights(nominee, 0)`, which properly cleans slopes. Then `removeNominee` with oldWeight≈0 → no underflow.
3. **Health monitoring**: Off-chain script tracking sum drift and unrevoked voters.

Redeployment is impractical due to complex state (per-nominee per-week bias/slope, per-user per-nominee vote slopes, scheduled slope changes) that cannot be easily migrated.

### Low: Burner.sol has zero test coverage

No tests exist for the 66-LOC Burner contract.

### Notes (7)
1. FxPortal `setFxRootTunnel`/`setFxChildTunnel` lack access control (library, deployment already complete)
2. VoteWeighting `addNomineeEVM`/`addNomineeNonEVM` are permissionless (design choice, sybil/spam risk)
3. OLAS `mint()` silently returns without minting when inflation control fails (documented design)
4. GovernorTimelockControl `governorDelay` can desync from timelock `minDelay` (documented, circular dependency)
5. ProcessBridgedDataWormhole hardcoded TIMELOCK address (inconsistency with Arbitrum verifier)
6. Mixed Solidity pragma versions (^0.8.15 to ^0.8.30)
7. C4A fix revert paths untested (ProcessBridgedDataArbitrum 70%, ProcessBridgedDataWormhole 78.57% branch coverage)

## Methodology Compliance

308+ checklist items verified across all playbook checklists:

| Checklist | Items | Checked | New Findings | N/A |
|-----------|:-----:|:-------:|:------------:|:---:|
| C1-C12 (Access Control/Proxy/Init) | 12 | 12 | 0 | 8 |
| T1-T12 (Token Handling/Arithmetic) | 12 | 12 | 0 | 3 |
| T13-T35 (Token Advanced) | 23 | 23 | 0 | 23 |
| D1-D22 (DoS/Gas Griefing) | 22 | 22 | 0 | 17 |
| L1-L65 (Business Logic Edge Cases) | 65 | 65 | 0 | 42 |
| DeFi Attack Patterns 1-140 | 140 | 140 | 0 | 98 |
| Access Control Patterns A-N | 14 | 14 | 0 | 5 |
| Token & Reward Patterns | 20+ | 20+ | 0 | 18 |
| **Total** | **~308** | **~308** | **0** | **~214** |

~70% of DeFi attack patterns are N/A — this is a governance/bridge protocol with no oracle, lending, liquidation, pools, swaps, ERC4626, or flash loans.

## Phases Completed

- Phase 0: Protocol classification, trust model (owner=Timelock HIGH trust), known issues PDF (10 items), C4A findings review
- Phase 2: Slither (242 results, all triaged), coverage (98.48% stmt / 93.56% branch), compilation
- Phase 3: Manual review of all 27 contracts
- Phase 3.5: Full EVM checklist (134 items), DeFi attack patterns (140 items), access control + token patterns
- Phase 3b: Deep dives — removeNominee slope lifecycle, FxPortal deployment scripts, bridge parameter matrix
- Phase 3c: Cross-reference with `docs/Vulnerabilities_list_governance.md` (10 known issues)
- Phase 4: Checklist compliance report

## Cross-reference with Known Vulnerabilities

All 10 items from `docs/Vulnerabilities_list_governance.md` confirmed. Our removeNominee finding (Low) extends PDF #8 which only mentions orphaned voting power — the slope drift and potential DoS path at line 611 are NEW, though practical exploitation requires rare conditions.

## Key Defensive Properties Verified

- All bridge messengers validate both transport layer (msg.sender) AND source governor address
- veOLAS is non-transferable — flash loan governance attack impossible
- All loops bounded (MAX_NUM_WEEKS=250, 255 for checkpoints, 128 for binary search)
- All low-level `.call()` return values checked
- All type casts preceded by bounds checks (uint96 max for amounts)
- Rounding consistently favors protocol (truncation in slope/weight calculations)
- GuardCM explicitly blocks delegatecall from multisig
- No proxy/upgradeable patterns — no storage collision risk
