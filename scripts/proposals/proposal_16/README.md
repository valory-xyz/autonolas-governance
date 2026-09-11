# Proposal 16 — Olas on Robinhood Chain: wave 2

Connects the L1 side of the Robinhood Chain (4663) deployment. All three entries are **direct L1
Timelock calls** — nothing is bridged, so every effect is observable on a mainnet fork and there is no
destination-chain leg to simulate.

**Pre-computed proposalId:**
`0x5404dbff11349c43360d7add3424456fb93e7e98274b4bdcc8e6e9ac39a4cd0d`

**descriptionHash:** `0xec7083866e6168ff9b80e04f8f2b35f85524544df4c47c4cca3d365fa6e707be`

## What it does

| # | Target | Call |
|---|---|---|
| 0 | [`Dispenser`](https://etherscan.io/address/0x5650300fCBab43A0D7D02F8Cb5d0f039402593f0) | `setDepositProcessorChainIds([0xb9DfcC61…], [4663])` |
| 1 | [`GuardCM`](https://etherscan.io/address/0xC0b146D61e2A2C17E024477E01978D1Fcf598c6B) | `setBridgeMediatorL1BridgeParams([inbox], [verifier], [4663], [mediator])` |
| 2 | [`GuardCM`](https://etherscan.io/address/0xC0b146D61e2A2C17E024477E01978D1Fcf598c6B) | `setTargetSelectorChainIds(…)` — four triples on 4663: `pause()` ×2, `drain()`, `drain(address)` |

### Why now

Wave 1 is complete. All 28 Olas contracts on 4663 are deployed and verified on Sourcify, and on
2026-09-11 the ten owner-bearing ones were transferred to the chain's governance control point — the
DAO already controls the deployment. What is missing is purely on L1: the Dispenser does not know the
chain exists, and GuardCM holds no route for it.

The ownership handover deliberately preceded this proposal. While `ArbitrumTargetDispenserL2` was owned
by the deployer EOA, that key could `pause()` then `migrate()` the dispenser's entire OLAS balance;
registering the processor first would have opened a window in which incentives could be drained as soon
as they arrived. That window is now closed permanently.

### 0 — register the deposit processor

`mapChainIdDepositProcessors(4663)` is `address(0)` today, so any staking-incentive claim for a 4663
nominee reverts. The processor `0xb9DfcC6155Ba4F211DCf8e6eCc9976Be11bB7a77` reports
`l2TargetChainId() == 4663`.

### 1 — register the bridge route in GuardCM

Robinhood Chain is an Arbitrum Orbit rollup and reuses the same `ProcessBridgedDataArbitrum` verifier as
Arbitrum One, keyed on its own Delayed Inbox.

### 2 — allowlist exactly the selector set the other chains hold

Four triples, all on 4663, taken from what GuardCM **actually** holds elsewhere rather than from what
looked reasonable:

| target | selector | on other chains |
|---|---|---|
| `ServiceManagerProxy` `0x63e66d7a…` | `pause()` `0x8456cb59` | `true` on all seven |
| `ArbitrumTargetDispenserL2` `0xc40C79C2…` | `pause()` `0x8456cb59` | `true` on all seven |
| `ServiceRegistryL2` `0xE3607b00…` | `drain()` `0x9890220b` | `true` on all seven |
| `ServiceRegistryTokenUtility` `0x3d77596b…` | `drain(address)` `0xece53132` | `true` on all seven |

**`unpause()` is deliberately excluded.** It reads `false` on every chain for both pausable targets. An
earlier revision of this proposal granted it and was caught in review. Granting it would let the
community multisig lift a pause on 4663 in a single transaction with no vote: the CM holds the
Timelock's `PROPOSER_ROLE` and `EXECUTOR_ROLE`, `getMinDelay()` is `0`, and GuardCM is the CM Safe's
guard, so this allowlist is the only constraint. The fork test asserts both `unpause` triples stay
`false` after execution.

The two `drain` selectors were added for the same parity reason, in the opposite direction: proposal 11
set them on every chain, and without them 4663 would be the only chain where draining slashed funds
needs a full governance cycle. Draining is not containment, so including them does not contradict the
description.

**Entries 1 and 2 must ship together.** Mode is the cautionary case: its allowlist entries were
backfilled in July 2026 but `setBridgeMediatorL1BridgeParams` was never called, leaving `verifierL2 == 0`
and every CM transaction to Mode failing closed for two months, until proposal 13 repaired it. An
allowlist without bridge params is not a partial capability — it is none.

## Address collision — expected, do not "fix" it

Two constants are shared with the Arbitrum One route and will look wrong on review:

| constant | value | why it is shared |
|---|---|---|
| bridge mediator L2 | `0x4d30F68F5AA342d296d4deE4bB1Cacca912dA70F` | `alias(L1 Timelock)`. The Orbit aliasing rule (`+0x1111…1111 mod 2^160`) is **chain-independent**, so two Orbit chains aliasing the same Timelock yield the same address. |
| verifier | `0x0F33636698F6607B2FDdC1e857788535914C44d4` | one `ProcessBridgedDataArbitrum` serves every Orbit chain. |

Reading GuardCM's existing Arbitrum entry returns exactly this verifier **and** exactly this mediator;
only the inbox and the chain Id distinguish the two routes. Verified independently: the same address
holds nonce 12 on Arbitrum One — the DAO has driven it there twelve times — and on 4663 it is the
`owner()` of all ten handed-over contracts.

Because two of the three fields are identical, an accidental overwrite of the Arbitrum route would leave
most of the entry looking correct. The fork test asserts Arbitrum's entry is untouched, chain Id
included.

## Validation

L1 fork test: [`Proposal16Robinhood.t.sol`](../../../test/proposals/Proposal16Robinhood.t.sol)

```
forge test --match-contract Proposal16RobinhoodTest -vv
```

- `test_preconditions` — every field this proposal sets is unset first (so the test proves something),
  with the populated Arbitrum route as a positive control that the getters are not silently returning
  zero.
- `test_L1_fullGovernanceLifecycle` — propose → vote → queue → execute through the **live**
  GovernorOLAS, asserting the governor assigns the same `proposalId` the artifacts publish, then
  checking all three effects and the Arbitrum non-regression.
- `test_CM_canPause4663_onlyAfterProposal` — what the guard actually **admits**, not just what it
  stores. Builds a real community-multisig `schedule` carrying an Orbit retryable to 4663 and runs it
  through `GuardCM.checkTransaction`: rejected before the proposal with a pinned
  `NotAuthorized(inbox, createRetryableTicket, 1)`, accepted after for both pausable targets, and
  `unpause()` still refused. This is the Mode lesson made executable — Mode's storage said yes while
  the guard said no.

All three pass. `Governor.execute()` uses ~266k gas.

No Tenderly simulation is required: there is no bridged payload.

## Regenerating the artifacts

```bash
forge script scripts/proposals/proposal_16/Proposal16Robinhood.s.sol:Proposal16Robinhood > /tmp/run.txt
# parse the entry blocks into calldata.json, then:
node scripts/proposals/proposal_16/annotate.js "Proposal 16 — Olas on Robinhood Chain: wave 2"
```

`description.txt` must match the builder's `DESCRIPTION` byte-for-byte — the `proposalId` is computed
over its hash. Both currently hash to `0xf9a031f3…`, and `annotate.js` recomputes the `proposalId` in
ethers independently of the Solidity builder; the two agree.
