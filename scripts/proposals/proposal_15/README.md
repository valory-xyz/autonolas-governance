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

**Threshold — 250,000 is the top of a flat band.** Live voting power is concentrated: the five largest
positions are all above 250,000 veOLAS and the sixth is below 16,000, so every threshold between those two
levels admits the same five addresses. Taking the top of the band maximises the cost of an attempt without
excluding anyone a lower level inside the band would admit. Against *today's* setting it is a real
restriction, and the description says so: twelve addresses clear 5,000, five clear 250,000, and holders in
between regain eligibility by increasing or extending a lock.

**Quorum — why 10.** Bravo counts only For votes toward quorum (`COUNTING_MODE()` is
`support=bravo&quorum=bravo`; `_quorumReached` is `quorum(snapshot) <= forVotes`), so quorum is the floor an
*unopposed* proposal must reach — the threshold is only the entry fee. Every proposal in this Governor's
history was carried by a single voter fielding between 286,101 and 1,126,974 votes, and at a 10% numerator
each of the four largest positions still clears quorum on its own. 15% would require two voters to
coordinate, which has never happened.

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

## Reproduce

```bash
forge script scripts/proposals/proposal_15/Proposal15GovernorParams.s.sol:Proposal15GovernorParams
ETH_RPC_URL=<rpc> forge test --match-contract Proposal15 -vv
```

The test asserts the builder's bytes, the published id and descriptionHash, that the description ends with
the DAO Constitution reference, and then runs the full lifecycle on a fork — propose, vote, queue, execute —
checking `proposalThreshold`, `quorumNumerator`, `proposalEta == queue + governorDelay`, and that a
snapshotted proposal keeps the 3% bar. The lifecycle uses a rehearsal description so the suite keeps working
after the real proposal is on-chain; the published bytes are checked in a view-only test.

Analysis behind the parameter choice lives in `autonolas-analytics` under `governance/`.
