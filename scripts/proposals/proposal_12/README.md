# Proposal 12 — Un-nominate legacy staking contracts

Removes the **20 remaining legacy staking program nominees** from
[`VoteWeighting`](https://etherscan.io/address/0x95418b46d5566D3d1ea62C12Aea91227E566c5c1) via
`removeNominee(bytes32 account, uint256 chainId)`. Follow-up to the executed 32-nominee cleanup
(prepared as proposal 25 in the `autonolas-registries` repo): these 20 were still live programs
at that time and have since been superseded by the new staking contract generation (Omenstrat,
Polystrat, Basius, Optimus I–III), which **stays nominated**. 20 entries, all `values` = 0; every
call is a **direct L1 Timelock call** — VoteWeighting tracks nominees for every chain via the
`chainId` argument, so there are **no L2 bridge messages** in this proposal.

**Pre-computed proposalId:**
`114444441880073852265133011449819716331211044138342982360655448765431286854004`
(= `0xfd05423555e942a8a6980557e5796fe68423f15f7613a4058fa2fa46972ff174`)

## What it removes

| Chain | Count | Nominees |
|---|---|---|
| Gnosis (100) | 8 | Pearl Beta Mech Marketplace I–VIII |
| Polygon (137) | 3 | Polymarket Alpha - III, Polymarket Beta - I, Polymarket Beta - II |
| Optimism (10) | 3 | Optimus Alpha II, III, IV |
| Base (8453) | 6 | Pett.AI Agent Staking Contract 1–2, Agents.fun 1–3, one unused contract with invalid metadata |

All 20 targets were verified live nominees at drafting time, carrying a **negligible aggregate
vote weight** (~0.24% of `getWeightsSum()`, all of it on Polymarket Alpha - III) — voting weight
has already migrated to the new staking generation.

**Kept as live nominees (NOT in this proposal):** LST (Gnosis) — still carries active vote
weight — and the 16 new-generation contracts (Omenstrat I–VII, Polystrat I–III, Basius I–III,
Optimus I–III). The fork test asserts they survive untouched.

## Irreversibility

`removeNominee` is **permanent**: `mapRemovedNominees[nomineeHash]` is set on removal and never
cleared, and `_addNominee` reverts `NomineeRemoved` for such a hash — from any caller, including
the owner. Re-enabling a removed program would require deploying a new contract at a new address.

## Execution timing constraint

`VoteWeighting.removeNominee` routes through `Dispenser.removeNominee`, which reverts `Overflow`
if called within the last week of the ongoing epoch (`block.timestamp >= epochEnd - 1 week`).
The proposal **must be executed with > 7 days left in the epoch** (epoch length is 14 days).
`removeNominee` also reverts `NomineeDoesNotExist` for a non-live nominee; since all 20 calls
execute atomically in one Timelock batch, none of the targets may be removed by other means
between submission and execution.

## Files

| File | Purpose |
|---|---|
| `Proposal12Unnominate.s.sol` | Forge builder — single source of truth for the 20 `(target, value, calldata)` entries and the `DESCRIPTION`. `forge script … :Proposal12Unnominate` prints the arrays. |
| `description.txt` | Canonical proposal description (matches the builder's `DESCRIPTION` byte-for-byte; the proposalId is computed from it). |
| `calldata.json` | The builder's emitted `[{index,target,value,calldata}]`, used to generate the HTML. |
| `annotate.js` | Decodes `calldata.json` + `description.txt` → the annotated `proposal_12.html` (and computes the proposalId). |
| `proposal_12.html` | Self-contained annotated breakdown: copy-paste `propose()` arrays, decoded selectors/args/addresses, raw calldata per entry, proposalId. |

## Regenerate (only if addresses/description change)

```bash
forge script scripts/proposals/proposal_12/Proposal12Unnominate.s.sol:Proposal12Unnominate > /tmp/run.txt
# re-extract calldata.json from the run output, then:
node scripts/proposals/proposal_12/annotate.js "Proposal 12 — un-nominate legacy staking contracts"
```

## Testing

**L1 (Forge fork test):** [`test/proposals/Proposal12Unnominate.t.sol`](../../../test/proposals/Proposal12Unnominate.t.sol)
runs three tests against a mainnet fork:
- `test_preconditions` — all 20 targets are live nominees; aggregate weight being removed < 1% of `getWeightsSum()`;
- `test_L1_fullGovernanceLifecycle` — full propose → vote → queue → execute through the live
  GovernorOLAS; all 20 removed, LST + new generation still nominated; `execute()` measured at
  **5,535,179 gas** vs the EIP-7825 per-tx cap of 16,777,216 (asserted under cap);
- `test_L1_fullProposal_executesAsTimelock` — fast path executing the batch directly as the Timelock.

```bash
forge test --match-contract Proposal12UnnominateTest -vvv
```

There are no L2 effects to simulate — all calls are local to Ethereum.
