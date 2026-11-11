# Proposal 17 — Marketplace, ServiceManager/Safe and StakingToken activation

Activates implementations already deployed and on-chain-checked (addresses recorded in
[autonolas-marketplace #211](https://github.com/valory-xyz/autonolas-marketplace/pull/211) and
[autonolas-registries #343](https://github.com/valory-xyz/autonolas-registries/pull/343)). **No new
contract code** — every target is already live; this proposal only flips proxy implementations and
allowlist/permission entries.

**Pre-computed proposalId:**
`800828120181505465882162548520110504832833383217755599275808806715811518961`
(= `0x01c540ade3e498b3c0aa1e2aa9cfd0de1f861153ba73d8bf88efcbd72fb159f1`)

**descriptionHash:** `0x2c993df6c6f3923fdfd1064c99f29c009f1fe6292dc8681ecc84ee341723bacc`
(`description.txt` matches the builder's `DESCRIPTION` byte-for-byte — no trailing newline — so
hashing the file reproduces this id.)

**Total ETH value:** `1907400000000000` wei (≈0.0019 ETH) — the 15 Arbitrum/Robinhood retryable
tickets, each with a **per-call** submission fee.

## Execution funding

The Timelock holds no ETH. **The deployer EOA transfers the exact total (`1907400000000000` wei) to
the Timelock before `Governor.execute`.** Each retryable's submission fee is sized per call at an L1
base-fee ceiling of **50 gwei** (`(1400 + 6·len)·50 gwei`); any excess is refunded to the Timelock's
L2 alias. **Execution must occur while L1 base fee ≤ 50 gwei**, or either Inbox reverts the whole
execution. The L1 fork test funds the Timelock and runs all 28 actions at exactly 50 gwei.

## What it does

- **Marketplace (8 chains, no Mode):** each `MechMarketplace` proxy → `changeImplementation`
  (1.1.0 → 1.2.0) + `setMechFactoryStatuses` enabling the new native/USDC factories and disabling the
  superseded ones (OLAS factories stay disabled).
- **ServiceManager + Safe wrapper (9 chains):** each `ServiceManager` proxy → `changeImplementation`
  (1.2.0 → 1.3.0); each service registry → `changeMultisigPermission(newWrapper, true)` then
  `changeMultisigPermission(oldWrapper, false)`. **Robinhood also** revokes the deprecated
  same-address Safe adapter (`0xFbBEc0C8…2aB`).
- **StakingToken (9 chains):** each `StakingVerifier` → `changeStakingLimits(1e22, 2592000, 44, 3e18)`
  (only `numServicesLimit` changes, 100 → 44) + `setImplementationsStatuses` allowlisting 0.4.0 and
  disabling the superseded implementation(s) (StakingNativeToken excluded). **Celo** disables two
  superseded impls (0.2.0 `0xe1E1…b7a9` and 0.3.0 `0xd2ff4Cf0…ca7b9`); every other chain has one.

The complete superseded set was derived by replaying each verifier's `ImplementationsWhitelistUpdated`
events: all chains enable only their 0.2.0; Celo also had 0.3.0.

## Routing (28 top-level entries)

| Entries | Chain(s) | Route |
|---|---|---|
| 0–6 | Ethereum | direct Timelock calls |
| 7 | Gnosis | AMB → HomeMediator (packed multicall) |
| 8 | Polygon | FxRoot → FxGovernorTunnel (packed multicall) |
| 9–12 | Optimism, Base, Celo, Mode | OP-stack `sendMessage` → `processMessageFromSource` (packed multicall; Mode carries ServiceManager + StakingToken only) |
| 13–19 | Arbitrum | 7 retryable tickets straight to each target |
| 20–27 | Robinhood | 8 retryable tickets (incl. the Safe-adapter revocation) |

Mediator chains pack all of that chain's calls into **one** atomic message. Arbitrum and Robinhood
have no mediator — their targets are owned directly by the L2 alias of the L1 Timelock
(`applyL1ToL2Alias(Timelock) = 0x4d30…da70f`, codesize 0), so each call is its own retryable ticket,
enable-before-disable ordered, and **not atomic** on those two chains.

## Partial-execution states and recovery (Arbitrum / Robinhood)

The L1 `execute` creates all retryable tickets atomically; only their **L2 redemption** can fail
independently. Acceptable intermediate states and recovery:

- **A wrapper-enable ticket redeems but a later ticket does not:** the new wrapper is live; re-submit
  the failed ticket (manual redemption on the destination) — no state is lost.
- **A wrapper-disable ticket fails after the enable redeemed:** both old and new wrappers are briefly
  enabled (safe); re-submit the disable ticket.
- **A `changeStakingLimits` ticket redeems but `setImplementationsStatuses` does not** (or vice-versa):
  the verifier temporarily has the new limit but the 0.4.0 allowlist is not yet applied, or vice
  versa; re-submit the failed ticket. No instance creation depends on an intermediate state.
- A failed ticket is always re-executable by redeeming it on the destination; nothing requires
  re-running the L1 proposal.

## Build / inspect

```bash
forge test --match-contract Proposal17Emit -vv                 # emit 28 entries + proposalId + descriptionHash
ETH_RPC_URL=<rpc> forge test --match-contract Proposal17ForkL1 -vv      # L1 execution + Inbox-fee fork test
ETH_RPC_URL=<rpc> forge test --match-contract Proposal17GovernorGas -vv # gas through the live Governor.execute
# destination legs (public RPC defaults; override per chain to avoid rate limits):
OPTIMISM_RPC=<rpc> POLYGON_RPC=<rpc> forge test --match-contract Proposal17L2Legs -vv
```

`Proposal17Activation.s.sol` is the single source of truth; `calldata.json` holds the copyable
`propose()` inputs (targets/values/calldatas); `proposal_17.html` is the annotated, self-contained
breakdown with full addresses, decoded calls and the copyable arrays.

## Validation status

- [x] Builder compiles; emit test asserts 28 entries; all inner-call and bridge selectors verified.
- [x] **L1 execution fork test** (`Proposal17ForkL1`) — funds the Timelock from the EOA, executes all 28
      actions at the 50 gwei ceiling (no revert → both Inbox submission fees hold), asserts the Ethereum
      end state.
- [x] **Governor.execute gas** (`Proposal17GovernorGas`) — measured through the live GovernorOLAS
      lifecycle with the final payload: **2,092,685 gas** (well under the 16,777,216 per-tx cap); state
      reaches EXECUTED.
- [x] **Per-L2 destination fork tests** (`Proposal17L2Legs`) — all 8 legs pass on destination-chain
      forks: simulated bridge delivery to each mediator (Gnosis AMB, Polygon FxPortal, OP-stack
      Optimism/Base/Celo/Mode) and aliased-Timelock delivery for Arbitrum/Robinhood retryables, each
      asserting that every inner call took effect (derived from the proposal's own calldata).
- [ ] **End-to-end retryable redemption + refunds** on Arbitrum and Robinhood — inherently post-submission
      (actual L2 ticket redemption and excess-fee refund to the L2 alias).

## Not included

Pause-row additions for the forthcoming Dispenser (proxy not yet deployed — deferred to a small
follow-up). No dispenser / VoteWeighting / treasury call.
