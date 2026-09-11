# Proposal 16 — Olas on Robinhood Chain: wave 2

Connects the L1 side of the Robinhood Chain (4663) deployment. All three entries are **direct L1
Timelock calls** — nothing is bridged, so every effect is observable on a mainnet fork and there is no
destination-chain leg to simulate.

**Pre-computed proposalId:**
`62593737919851794374564726850038659676331337351142765248604965204946966280314`
(= `0x8a62ccd8de4967a138016abc39c7f8040506ba259f202027389bd042374ff87a`)

**descriptionHash:** `0xf9a031f3b7e49df83c87f1a00521ff03d6039fd1f48c5135a58f5af4eec6c376`

## What it does

| # | Target | Call |
|---|---|---|
| 0 | [`Dispenser`](https://etherscan.io/address/0x5650300fCBab43A0D7D02F8Cb5d0f039402593f0) | `setDepositProcessorChainIds([0xb9DfcC61…], [4663])` |
| 1 | [`GuardCM`](https://etherscan.io/address/0xC0b146D61e2A2C17E024477E01978D1Fcf598c6B) | `setBridgeMediatorL1BridgeParams([inbox], [verifier], [4663], [mediator])` |
| 2 | [`GuardCM`](https://etherscan.io/address/0xC0b146D61e2A2C17E024477E01978D1Fcf598c6B) | `setTargetSelectorChainIds(…)` — four `pause()`/`unpause()` triples on 4663 |

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

### 2 — allowlist the pause/unpause triples

Four triples, all on 4663: `ServiceManagerProxy` and `ArbitrumTargetDispenserL2`, each with `pause()`
(`0x8456cb59`) and `unpause()` (`0x3f4ba83a`). This is the fast-path containment the community multisig
holds on every other chain.

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

Both pass. `Governor.execute()` uses ~266k gas.

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
