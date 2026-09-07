# Proposal 15 — raise the Governor's proposal threshold and quorum

Two actions, both on the Governor itself. Both setters are `onlyGovernance`, whose executor is Timelock A,
so a governance proposal is the only route to either. No value, no bridge, no external contract.

**Pre-computed proposalId:**
`3563000702947626407249966116394330391891319244018918786718598572660765109424`
(= `0x07e0964139076aa8385757a2fa0f0d05865f9174a3a1ef0bddad7b6188e22cb0`)

**descriptionHash:** `0xbc86418e14715cfad78c62576109d9825e2b1b7395fb5f3a594cc64eef35f8b1`

## What it does

| # | Target | Call | From | To |
|---|---|---|---:|---:|
| 0 | Governor `0x060D0CBd…51E6` | `setProposalThreshold(uint256)` | 5,000e18 | **250,000e18** |
| 1 | Governor `0x060D0CBd…51E6` | `updateQuorumNumerator(uint256)` | 3 | **10** |

## Why

A proposal created on 2026-09-05 asked the DAO to transfer Treasury ownership to an externally owned
account. Its proposer held 5,100 OLAS — just over the 5,000 veOLAS minimum, which has not been revisited
since deployment.

**Threshold — 250,000 sits inside a flat band, deliberately below its top.** Live voting power is
concentrated: the five largest positions are 982,733 / 856,538 / 838,898 / 409,732 / 293,929 and the sixth
is 15,880, so every threshold in `(15,880 … 293,929]` admits exactly the same five addresses. **The top of
that band is 293,929, not 250,000.** The ~15% gap is deliberate: veOLAS power decays continuously, so the
band's edges move every block, and the Bravo-cancel cap below wants margin too. Any point in the band
excludes the same people — the choice within it is about headroom, not about who can propose. Against
*today's* setting it is a real restriction, and the description says so: twelve addresses clear 5,000, five
clear 250,000, and holders in between regain eligibility by increasing or extending a lock.

**Quorum — why 10.** Bravo counts only For votes toward quorum (`COUNTING_MODE()` is
`support=bravo&quorum=bravo`; `_quorumReached` is `quorum(snapshot) <= forVotes`), so quorum is the floor an
*unopposed* proposal must reach — the threshold is only the entry fee.

The case rests on **position capacity, not on past turnout**, and the distinction matters. The five non-zero
votes ever cast here are 286,101 / 288,933 / 294,537 / 859,475 / 1,126,974: at `P` = 3,476,854 a 10%
numerator puts quorum at 347,685, so **three of those five — the three lowest — would not have carried a
proposal alone**. What the change relies on is that each of the four largest *positions* clears the new bar
by itself, which they do. After the defensive relocking of 2026-09-07, `P` is 8,394,665 and a 10% quorum is
839,466 — still cleared alone by each of the three largest positions, which now hold about 2.5M each.

15% is the next rung and is not obviously wrong either; 10 is the conservative choice, not a sharp
boundary.

## The cap that makes this safe

`GovernorCompatibilityBravo.cancel(proposalId)` is permissionless once the **proposer's** power sits below
`proposalThreshold()`. A threshold above the power of the address that creates the DAO's proposals would
make the DAO's own live proposals cancellable by anyone. 250,000e18 is deliberately below it — asserted in
the test, and worth re-checking before execution, since veOLAS power decays continuously.

## Nothing in flight is affected

`quorum(blockNumber)` reads `quorumNumerator(blockNumber)` from a checkpoint history, so proposals already
snapshotted keep the 3% bar. The new numerator binds *at* the execution block: the checkpoint is written
with key `block.number` and the lookup is inclusive.

## What this is not

Neither change defends the Treasury against a funded proposer. Both raise the cost of putting a proposal in
front of the DAO that it must then mobilise to defeat.

## Files

| File | Purpose |
|---|---|
| `Proposal15GovernorParams.s.sol` | Forge builder — single source of truth for the two `(target, value, calldata)` entries and the `DESCRIPTION`. |
| `description.txt` | Canonical proposal description; matches the builder byte-for-byte, asserted by `test_committedArtifactsMatchTheBuilder`. |
| `calldata.json` | The builder's emitted `[{index,target,value,calldata}]`, used to generate the HTML. |
| `annotate.js` | Decodes `calldata.json` + `description.txt` → `proposal_15.html`, and recomputes the proposalId independently of both the builder and the test. |
| `proposal_15.html` | Self-contained annotated breakdown: copy-paste `propose()` arrays, decoded selectors and arguments, raw calldata per entry, proposalId. |

## Regenerate (only if the parameters or the description change)

```bash
forge script scripts/proposals/proposal_15/Proposal15GovernorParams.s.sol:Proposal15GovernorParams > /tmp/run.txt
# parse the entries into calldata.json, then:
node scripts/proposals/proposal_15/annotate.js "Proposal 15 — raise proposalThreshold to 250,000 veOLAS and quorum to 10%"
```

## Reproduce

```bash
forge script scripts/proposals/proposal_15/Proposal15GovernorParams.s.sol:Proposal15GovernorParams
ETH_RPC_URL=<rpc> forge test --match-contract Proposal15 -vv
```

Six tests. The builder's bytes; the published id, checked both locally **and against the deployed
Governor's own `hashProposal`**; `description.txt` and `calldata.json` byte-matching the builder; the DAO
Constitution reference at the end of the description; the full lifecycle on a fork — propose, vote, queue,
execute — checking `proposalThreshold`, `quorumNumerator`, `proposalEta == queue + governorDelay`, and that
a snapshotted proposal keeps the 3% bar; and both directions of the cancel guard, behaviourally: the
hostile 2026-09-05 proposal becomes cancellable by anyone after execution, and proposal 13 does not.

Post-execution the suite also asserts what the sections above claim: the DAO proposer keeps **2×** headroom
over the new threshold (a bare `>` would first fail on the day the cap is already breached, and
`proposalThreshold` is not checkpointed, so the cancel gate reads it live), and the largest holder still
clears both the new threshold and the new quorum — the one failure mode that cannot be undone by
governance if it is wrong. The lifecycle uses a rehearsal description so the suite keeps working
after the real proposal is on-chain; the published bytes are checked in a view-only test.

Analysis behind the parameter choice lives in `autonolas-analytics` under `governance/`.
