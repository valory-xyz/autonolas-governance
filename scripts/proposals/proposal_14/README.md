# Proposal 14 — sync the L2 withheld OLAS amounts back to L1

Seven actions, one per chain that holds a withheld balance, each instructing that chain's staking
target dispenser to report its withheld OLAS amount back to the L1 `Dispenser`. All seven are
bridged; six go through a governance receiver, and Arbitrum goes through a retryable ticket.

**Pre-computed proposalId:**
`40126612048141097336620033593318472673469120154184180144739203820830139231953`
(= `0x58b6db8a26f1f4bce2e9e454d299b4e0274d3f7186e0e58e695e4326f5f22ed1`)

**descriptionHash:** `0x993cbb52a409a856560c105510540d773c41589ee5a5b2e46247e5c66801f9ee`

## What it does

| # | Chain | Route | Withheld at build time (OLAS) |
|---|---|---|---:|
| 0 | Polygon | FxRoot → FxGovernorTunnel | 100,408.03 |
| 1 | Gnosis | AMB → HomeMediator | 2,620,457.10 |
| 2 | Optimism | L1CDM → OptimismMessenger | 225,834.65 |
| 3 | Base | L1CDM → OptimismMessenger | 1,380,908.80 |
| 4 | Celo | L1CDM → OptimismMessenger | 724.80 |
| 5 | Mode | L1CDM → OptimismMessenger | 703,245.03 |
| 6 | Arbitrum | Inbox retryable → dispenser directly | 724.80 |

Each entry calls `syncWithheldAmount(bytes)` on that chain's target dispenser. **≈ 5.03M OLAS in
total**, though the amounts are context rather than parameters — see below.

### Why

A target dispenser caps each staking deposit at what the target can accept
(`DefaultTargetDispenserL2._processData` → `verifyInstanceAndGetEmissionsAmount`) and keeps the
remainder as `withheldAmount`. `syncWithheldAmount` reports that figure to L1, where
`Dispenser.mapChainIdWithheldAmounts` **nets it against future transfers to the same chain**
(`Dispenser.sol:728-740` and `:1193-1207`).

**No tokens move.** The effect is that L1 stops sending OLAS to a chain that is already holding an
unspent balance, and that balance is drawn down over subsequent epochs instead.

**The path has never been used.** At build time every L2 `stakingBatchNonce` reads `0` and every
`mapChainIdWithheldAmounts` entry on L1 reads `0`, while the seven dispensers hold ~5.03M OLAS
between them.

### The amounts are not in the calldata

Each dispenser reads its own `withheldAmount` at execution time. The figures above are for voters,
not parameters: they move whenever a distribution is claimed, and that costs this proposal nothing.
Re-read them shortly before submission so the proposal text is current.

## ⚠ Two wire formats — do not mix them

| route | what the L1 call carries |
|---|---|
| **Polygon** | the packed buffer **directly** — FxChild calls `processMessageFromRoot` itself |
| **Gnosis, OP-stack** | the **encoded call** `processMessageFromForeign(bytes)` / `processMessageFromSource(bytes)` wrapping the packed buffer |

Passing the bare packed buffer on the second kind reaches the mediator with a garbage selector and
reverts **on the destination chain**, where it is expensive to notice: the L1 leg succeeds either
way, because `requireToPassMessage` and `sendMessage` only enqueue. The L2 leg tests are what
distinguish the two, which is why each one replays the builder's own `packedFor(...)` bytes.

The packed buffer is the receivers' shared format:
`target(20) | value(uint96,12) | payloadLength(uint32,4) | payload`.

## ⚠ Address collision

**`0x9338b5153AE39BB89f50468E608eD9d764B755fD`** is *both* Polygon's `FxGovernorTunnel` (entry 0's
receiver) and Mode's `OptimismMessenger` mediator (entry 5's receiver), through aligned deployer
nonces. Both meanings are used in this proposal. Each was verified by calling a chain-specific
getter **on the chain it is used on**:

| check | result |
|---|---|
| Polygon `0x9338b515…`.`fxChild()` | `0x8397259c…` |
| Polygon `0x9338b515…`.`rootGovernor()` | the L1 Timelock |
| Mode `0x9338b515…`.`CDMContractProxyHome()` | `0x4200000000000000000000000000000000000007` |
| Mode `0x9338b515…`.`sourceGovernor()` | the L1 Timelock |

The annotated HTML resolves the chain from the **L1 entrypoint**, never from the L2 address, so the
same address is labelled correctly in both entries.

## Arbitrum is shaped differently

There is **no governance receiver contract on Arbitrum**. The dispenser's owner is the L1 Timelock's
L2 **alias**:

```
0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE          (Timelock, Ethereum)
+ 0x1111000000000000000000000000000000001111        (Arbitrum alias offset)
= 0x4d30F68F5AA342d296d4deE4bB1Cacca912dA70F        = ArbitrumTargetDispenserL2.owner()
```

So a retryable ticket calls the dispenser **directly** and arrives already authorised. This is
asserted in `Proposal14ArbitrumLegTest.test_arbitrumOwnerIsTheTimelockAlias` rather than assumed,
because it is what makes entry 6 a different shape from the other six.

**Entry 6 is the only one carrying ETH**, and it is priced as a **ceiling rather than as today's
cost**. This is the detail that decides whether a proposal opened today still executes a week later.

The Inbox recomputes the submission fee **at execution**, as `(1400 + 6 × dataLength) × block.basefee`
— `1808 × basefee` for this 68-byte payload — and reverts if `maxSubmissionCost` is short. Because
entry 6 sits in the same batch as the rest, **that revert takes all seven entries with it.**

| | |
|---|---|
| base fee when priced | ~0.41 gwei |
| priced ceiling | **45 gwei** (~109x) |
| `maxSubmissionCost` | 1808 × 45 gwei = 81,360,000,000,000 |
| `gasLimit × maxFeePerGas` | 300,000 × 0.05 gwei = 15,000,000,000,000 |
| **entry 6 value** | **96,360,000,000,000 wei (≈ 0.0000964 ETH)** |
| Timelock balance | 0.0001 ETH — covers it, with no top-up and no ETH attached at execution |

`test_arbitrumEntrySurvivesABaseFeeSpike` asserts the ceiling **from both sides**: the entry still
executes at 45 gwei and stops executing above it, so the number is a fact rather than a comment.

**Why the L2 leg was trimmed to 0.05 gwei.** The Timelock's balance is the whole budget, and the two
shortfalls are not symmetric: an L1 shortfall **reverts the proposal**, while an L2 shortfall only
means the ticket must be redeemed by hand within 7 days. So the budget goes to the L1 side. 0.05 gwei
is still ~5x Arbitrum's 0.01 gwei floor.

**Over-pricing costs nothing but float** — the excess over the actual fee is refunded on L2. And
**sending ETH to the Timelock is permissionless**, so a higher ceiling is available at any time
without a vote: top it up, raise `ARB_MAX_SUBMISSION_COST`, regenerate.

> **A reverted execution is not a lost vote.** `execute()` can be retried, and a queued proposal has no
> deadline, so the fallback if the base fee is above the ceiling on the day is simply to execute in a
> calmer block.

### Refunds go to the alias, not to the Timelock

`excessFeeRefundAddress` and `callValueRefundAddress` are both the **aliased** Timelock
(`0x4d30F68F…a70F`), not `0x3C1fF68f…D95fE`. On Arbitrum the Timelock's own address belongs to nobody,
so a refund sent there would be permanently lost; the alias is spendable through this same governance
route. `test_arbitrumRefundsGoToTheAlias` decodes the committed calldata and asserts it.

## Preconditions verified on-chain

| check | value |
|---|---|
| `Dispenser.mapChainIdWithheldAmounts(cid)`, all seven chains | `0` — nothing ever synced |
| `Dispenser.mapChainIdDepositProcessors(cid)`, all seven | non-zero (control: the zeros above are real) |
| every L2 `stakingBatchNonce` | `0` |
| every L2 `withheldAmount` | equals the dispenser's own OLAS balance |
| every L2 `paused` | `1` (unpaused; `2` is paused) |
| `ArbitrumTargetDispenserL2.owner()` | the Timelock's L2 alias |
| Timelock ETH balance | 0.0001 ETH ≥ entry 6's 0.0000964 ETH |

## Files

| File | Purpose |
|---|---|
| `Proposal14WithheldSync.s.sol` | Forge builder — single source of truth for the 7 `(target, value, calldata)` entries and the `DESCRIPTION`. Exposes `packedFor()` / `syncCalldata()` so the L2 tests replay the proposal's own bytes. |
| `description.txt` | Canonical proposal description (matches the builder byte-for-byte). |
| `calldata.json` | The builder's emitted `[{index,target,value,calldata}]`, used to generate the HTML. |
| `annotate.js` | Decodes `calldata.json` + `description.txt` → `proposal_14.html` (and computes the proposalId). The value note is **derived from entry [6]'s own bytes** — `maxSubmissionCost`, the base fee it tolerates, and who funds it. Proposal 14 is the first with a non-zero value, so that branch had never run before and carried inherited prose that was false here. |
| `proposal_14.html` | Self-contained annotated breakdown: copy-paste `propose()` arrays, decoded selectors/args/addresses, raw calldata per entry, proposalId. |

## Regenerate (only if addresses, gas params or description change)

```bash
forge script scripts/proposals/proposal_14/Proposal14WithheldSync.s.sol:Proposal14WithheldSync > /tmp/run.txt
# re-extract calldata.json from the run output, then:
node scripts/proposals/proposal_14/annotate.js "Proposal 14 — sync L2 withheld amounts to L1"
```

## Testing

### L1 — Forge fork test

[`test/proposals/Proposal14WithheldSync.t.sol`](../../../test/proposals/Proposal14WithheldSync.t.sol),
7 tests against a mainnet fork:

- `test_preconditions` — nothing synced yet on any chain, every deposit processor configured as a
  positive control, every bridge entrypoint has code, and the Timelock can fund entry 6;
- `test_L1_fullGovernanceLifecycle` — propose → vote → queue → execute through the live GovernorOLAS,
  asserting each dispatch **against the bytes the builder produced for that entry**: every OP-stack
  entry matched on `(emitter, SentMessage target, message)`, the Polygon `StateSynced` payload equal
  to this proposal's packed buffer with `rootSender == Timelock`, and the AMB and Inbox events
  required to contain their entry's payload verbatim. Counting alone would not do: four entries share
  an event signature, so a count passes with two entries aimed at the same messenger, and a bare bool
  passes on unrelated AMB or Inbox traffic in the same block. `execute()` measured at
  **9,941,101 gas** against the EIP-7825 cap of 16,777,216;
- `test_L1_fullProposal_executesAsTimelock` — the same batch executed directly as the Timelock;
- `test_proposalIdMatchesCommittedDescription` — pins the descriptionHash and proposalId;
- `test_committedArtifactsMatchTheBuilder` — reads `description.txt` and `calldata.json` off disk and
  asserts they still match the builder, so the files the HTML and the submission are made from cannot
  drift;
- `test_arbitrumEntrySurvivesABaseFeeSpike` — the entry executes at its priced 45 gwei ceiling and
  fails above it, so the buffer is asserted from both sides;
- `test_arbitrumRefundsGoToTheAlias` — decodes the committed calldata and pins both refund addresses
  to the alias.

```bash
ETH_RPC=<mainnet rpc> forge test --match-contract Proposal14WithheldSyncTest -vvv
```

### L2 — destination-chain validation

[`test/proposals/Proposal14L2Legs.t.sol`](../../../test/proposals/Proposal14L2Legs.t.sol), 15 tests
across seven chains.

**Each leg takes its input from `buildProposal()` and delivers the exact bytes the bridge would
deliver** — the `_message` out of `sendMessage`, the `_data` out of `requireToPassMessage`, the packed
buffer out of `sendMessageToChild`, the `data` out of `createRetryableTicket` — by low-level call.
Nothing re-encodes a wrapper or names a receiver by hand, because **a test that picks its own wrapper
cannot disagree with the builder about the wire format**, which is the thing most likely to be wrong.
The receiver and dispenser are read out of the calldata and then checked against that chain's expected
constants, so a mispaired (L1 entrypoint, L2 receiver, dispenser) triple fails here.

Both failure modes are proven caught, by mutating the builder and re-running:

| mutation | result |
|---|---|
| OP-stack leg hands the bare packed buffer to `sendMessage` (wrong wire format) | `entry has the wrong wrapper: 0xaea9ef99… != 0xd3042d2b…` |
| entry [3] pointed at Optimism's L1 messenger instead of Base's (mispairing) | `entry goes through the wrong L1 messenger: 0x25ace71c… != 0x866E82a6…` |

Each leg also has a negative test pinning the **exact** revert (`RootGovernorOnly` /
`ForeignGovernorOnly` / `SourceGovernorOnly`) rather than accepting any revert.

```bash
POLYGON_RPC=… GNOSIS_RPC=… OPTIMISM_RPC=… BASE_RPC=… CELO_RPC=… MODE_RPC=… ARBITRUM_RPC=… \
  forge test --match-contract "Proposal14.*LegTest" -vvv
```

**Arbitrum's `sendTxToL1` is the ArbSys precompile at `0x64`, which a plain EVM fork does not
implement** — the unmocked call dies with `InvalidFEOpcode`. The fork test mocks it, so the owner
gate, normalisation, dust and nonce are still covered. That the **real** precompile accepts this call
was established separately, against a live Nitro node:

```bash
cast call 0x5953f21495BD9aF1D78e87bb42AcCAA55C1e896C "syncWithheldAmount(bytes)" 0x \
  --from 0x4d30F68F5AA342d296d4deE4bB1Cacca912dA70F --rpc-url <arbitrum rpc>
# -> 0x  (succeeds)

cast call 0x5953f21495BD9aF1D78e87bb42AcCAA55C1e896C "syncWithheldAmount(bytes)" 0x \
  --from 0x000000000000000000000000000000000000bAd0 --rpc-url <arbitrum rpc>
# -> reverts OwnerOnly(0x…bad0, 0x4d30…a70F)
```

All 22 tests pass.

## After execution — this proposal is not finished when it executes

Every leg produces an **L2 → L1 message that somebody must claim**. Nothing arrives at the L1
`Dispenser` on its own:

| chain | claim | latency |
|---|---|---|
| Polygon | FxPortal exit — `receiveMessage(proof)` on the L1 deposit processor after the checkpoint | ~30–90 min |
| Gnosis | AMB validator signatures, then `receiveMessage` | hours |
| Optimism · Base · Celo · Mode | prove, then finalize the withdrawal | **7 days** |
| Arbitrum | `Outbox.executeTransaction` after the challenge period | **7 days** |

**Confirm per chain by reading `Dispenser.mapChainIdWithheldAmounts(chainId)` on L1** — it moves from
`0` to the synced amount. The proposal having executed proves nothing about the credit.

Record each leg's `amount` and `batchHash` at send time:
`Dispenser.syncWithheldAmountMaintenance(chainId, amount, batchHash)` (Timelock-only) is the fallback
for a message that never lands, and it must reproduce both exactly.
