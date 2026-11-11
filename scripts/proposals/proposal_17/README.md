# Proposal 17 — Marketplace, ServiceManager/Safe and StakingToken activation

Activates implementations already deployed and on-chain-checked (addresses recorded in
[autonolas-marketplace #211](https://github.com/valory-xyz/autonolas-marketplace/pull/211) and
[autonolas-registries #343](https://github.com/valory-xyz/autonolas-registries/pull/343)). **No new
contract code** — every target is already live; this proposal only flips proxy implementations and
allowlist/permission entries.

**Pre-computed proposalId:**
`32711718276225339996367009471891002262818557070323413596666025688182344427560`
(= `0x48522d2a4c1b4e2943d9461bb55a4fd8453a374b375db4644fec1e74c338a828`)

**descriptionHash:** `0x247167a5a4c70f47086152698e0679d94215e44b3e47fd49c23759877ffe8eca`

**Total ETH value:** `1349040000000000` wei (≈0.00135 ETH) — the 14 Arbitrum/Robinhood retryable
tickets (`96360000000000` wei each). The Timelock must hold at least this balance at execution.

> The on-chain description (`description.txt`) is deliberately kept to the facts of the calls and does
> not reference release phases, internal groupings or GitHub PRs. It matches the builder's
> `DESCRIPTION` byte-for-byte, so the proposalId is reproducible.

## What it does

- **Marketplace (8 chains, no Mode):** each `MechMarketplace` proxy → `changeImplementation`
  (1.1.0 → 1.2.0) + `setMechFactoryStatuses` enabling the new native/USDC factories and disabling the
  superseded ones (OLAS factories stay disabled).
- **ServiceManager + Safe wrapper (9 chains):** each `ServiceManager` proxy → `changeImplementation`
  (1.2.0 → 1.3.0); each service registry → `changeMultisigPermission(newWrapper, true)` then
  `changeMultisigPermission(oldWrapper, false)` (enable before disable).
- **StakingToken (9 chains):** each `StakingVerifier` → `changeStakingLimits(1e22, 2592000, 44, 3e18)`
  (only `numServicesLimit` changes, 100 → 44) + `setImplementationsStatuses([new0.4.0, superseded],
  [true, false], true)` (StakingNativeToken excluded).

## Routing (27 top-level entries)

| Entries | Chain(s) | Route |
|---|---|---|
| 0–6 | Ethereum | direct Timelock calls |
| 7 | Gnosis | AMB → HomeMediator (`requireToPassMessage` → `processMessageFromForeign`, packed multicall) |
| 8 | Polygon | FxRoot → FxGovernorTunnel (`sendMessageToChild`, packed multicall) |
| 9–12 | Optimism, Base, Celo, Mode | OP-stack `sendMessage` → `processMessageFromSource` (packed multicall; Mode carries ServiceManager + StakingToken calls only) |
| 13–19 | Arbitrum | 7 retryable tickets straight to each target (owner = aliased Timelock, no mediator) |
| 20–26 | Robinhood | 7 retryable tickets straight to each target (4663 Inbox) |

Mediator chains pack all of that chain's inner calls into **one** message (executed atomically on the
destination). Arbitrum and Robinhood have **no mediator** — their targets are owned directly by the
L2 alias of the L1 Timelock (`applyL1ToL2Alias(Timelock) = 0x4d30…da70f`, codesize 0 on both chains),
so each inner call is its own retryable ticket, enable-before-disable ordered; the wrapper
enable/disable are therefore **not atomic** on those two chains (accepted; one vote).

## Build / inspect

```bash
forge test --match-contract Proposal17Emit -vv   # emits all 27 entries + proposalId + descriptionHash
```

The builder `Proposal17Activation.s.sol` is the single source of truth; `description.txt` matches its
`DESCRIPTION` byte-for-byte.

## Validation status

- [x] Builder compiles; emit test asserts 27 entries; all inner-call and bridge selectors verified
      against proposals 13/14 (`0xdc8601b3` AMB, `0xb4720477` FxChild, `0x3dbb202b` OP sendMessage,
      `0x679b6ded` retryable; `0xd3042d2b`/`0xcd9e30d9` mediator entrypoints).
- [ ] **L1 Timelock fork test** (`test/proposals/`) — execute on a mainnet fork, assert the L1 effects
      (proxy versions + factory statuses + wrapper permissions + verifier limits/statuses), and measure
      the combined L1 execute gas.
- [ ] **Per-L2 destination validation** — Tenderly simulation of each bridged message (Mode via a
      destination Forge fork test, as Tenderly lacks Mode).
- [ ] **Retryable gas re-check on Robinhood** — 4663 basefee vs the Arbitrum-tuned parameters.

## Not included

Pause-row additions for the forthcoming Dispenser (proxy not yet deployed — deferred to a small
follow-up). No dispenser / VoteWeighting / treasury call.
