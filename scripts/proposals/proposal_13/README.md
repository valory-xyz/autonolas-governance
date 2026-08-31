# Proposal 13 — cross-chain housekeeping

Three unrelated maintenance actions batched into one vote. All three are submitted as L1 Timelock
calls; two carry a bridged payload to a destination chain.

**Pre-computed proposalId:**
`100619077063411664334557367612251066850008502834926962826958681194909586886778`
(= `0xde74612333738cde67026c99ae4d0019d30a06c861e83f6bceb1dd6cab33107a`)

**descriptionHash:** `0xfc97ad5c460cb572b31ee9f3c4bfb17e114055fdabfad7e56e0c8c07d30cdeb9`

## What it does

| # | Chain | Route | Call |
|---|---|---|---|
| 0 | Ethereum | direct | [`GuardCM`](https://etherscan.io/address/0xC0b146D61e2A2C17E024477E01978D1Fcf598c6B)`.setBridgeMediatorL1BridgeParams` — register the Mode (34443) route |
| 1 | Mode | Mode L1CrossDomainMessenger → mediator | [`StakingVerifier`](https://explorer.mode.network/address/0x87c511c8aE3fAF0063b3F3CF9C6ab96c4AA5C60c)`.setImplementationsStatuses([V1], [false], true)` |
| 2 | Polygon | FxRoot → FxGovernorTunnel | [`ServiceRegistryL2`](https://polygonscan.com/address/0xE3607b00E75f6405248323A9417ff6b39B244b50)`.changeMultisigPermission(PolySafeCreator, false)` |

### 0 — Mode bridge route in GuardCM

Proposal 11 configured GuardCM's bridge routes for Polygon, Gnosis, Arbitrum, Optimism, Base and
Celo, but not Mode. GuardCM therefore holds `verifierL2 == address(0)` for the Mode L1 messenger,
and every community-multisig transaction routed to Mode fails closed — Mode is the only supported
L2 where the CM cannot act. Mode is an OP-stack chain and reuses the same
`ProcessBridgedDataOptimism` verifier already used for Optimism, Base and Celo.

This is a fail-closed gap, so the change **adds** a capability and removes none.

### 1 — Mode staking allowlist

Removes a superseded V1 staking implementation from the Mode `StakingVerifier` allowlist. Nothing is
unwound: `StakingFactory` on Mode has emitted 7 `InstanceCreated` events, **all** against a different
implementation and **none** against this one.

> **`setCheck` must be `true`.** `setImplementationsStatuses` assigns `implementationsCheck = setCheck`
> **unconditionally**. Passing `false` would switch the allowlist off entirely and make
> `verifyImplementation()` return `true` for every implementation — the exact opposite of the intent.
> The Mode fork test asserts `implementationsCheck()` is still `true` after execution, which is the
> load-bearing assertion in that test.

### 2 — PolySafe retirement on Polygon

Removes `PolySafeCreatorWithRecoveryModule` from the whitelisted multisig implementations of the
Polygon service registry, closing registries vulnerability **#30** (a PolySafe creation can be
front-run, stranding the intended service identity) outright and with no code change.

**This is a product decision, not only a fix.** PolySafe is not dormant: the creator has emitted 259
`MultisigCreated` events, the most recent on 2026-08-15, although volume has fallen sharply (92 in
April 2026 → 3 in August 2026). After execution, a service that would have deployed a PolySafe
deploys an ordinary Safe instead. `GnosisSafeMultisig`
([`0x3d77596b…`](https://polygonscan.com/address/0x3d77596beb0f130a4415df3D2D8232B3d3D31e44)) remains
whitelisted and is the fallback; the Polygon fork test asserts it survives untouched. The change is
reversible by re-whitelisting, but any in-flight PolySafe deployment reverts in the meantime.

## ⚠ Address collisions — read before editing any constant

Three distinct contracts across this proposal share the numeric address
**`0x9338b5153AE39BB89f50468E608eD9d764B755fD`** through aligned deployer nonces:

| chain | contract | used here |
|---|---|---|
| Polygon | `FxGovernorTunnel` | yes — entry 2 receiver |
| Mode | `OptimismMessenger` mediator | yes — entry 1 receiver, and `bridgeMediatorL2` in entry 0 |
| Gnosis | `ServiceRegistryL2` | no |

and **`0x87c511c8aE3fAF0063b3F3CF9C6ab96c4AA5C60c`** is *both* Optimism's L2 messenger and Mode's
`StakingVerifier`.

A constant pointed at the wrong chain's contract looks correct on review. Each was therefore
verified by calling a chain-specific getter **on the chain it is used on**:

| check | result |
|---|---|
| Mode `0x9338b515…`.`CDMContractProxyHome()` | `0x4200000000000000000000000000000000000007` |
| Mode `0x9338b515…`.`sourceGovernor()` | the L1 Timelock |
| Polygon `0x9338b515…`.`fxChild()` | `0x8397259c…` |
| Polygon `0x9338b515…`.`rootGovernor()` | the L1 Timelock |
| Mode `0x87c511c8…`.`owner()` | the Mode mediator |
| Mode `0x87c511c8…`.`implementationsCheck()` | `true` |

The annotated HTML resolves the chain from the **L1 entrypoint**, never from the L2 address, so the
same address correctly links to polygonscan in entry 2 and to the Mode explorer in entry 1.

## Preconditions verified on-chain

| check | value |
|---|---|
| `GuardCM.owner()` | the Timelock |
| `GuardCM.mapBridgeMediatorL1BridgeParams(ModeL1CDM)` | `(0, 0, 0)` — unset |
| same getter for the Optimism L1CDM (control) | populated — so the zero above is real |
| Mode `StakingVerifier.mapImplementations(V1)` | `true` |
| Mode `StakingVerifier.implementationsCheck()` | `true` |
| Mode proxies created against V1 | **0** of 7 total |
| Polygon `ServiceRegistryL2.mapMultisigs(PolySafeCreator)` | `true` |
| Polygon `ServiceRegistryL2.owner()` | the FxGovernorTunnel |

## Files

| File | Purpose |
|---|---|
| `Proposal13Housekeeping.s.sol` | Forge builder — single source of truth for the 3 `(target, value, calldata)` entries and the `DESCRIPTION`. Also exposes `modeBridgePayload()` / `polygonBridgePayload()` so the L2 tests replay the proposal's own bytes. |
| `description.txt` | Canonical proposal description (matches the builder's `DESCRIPTION` byte-for-byte). |
| `calldata.json` | The builder's emitted `[{index,target,value,calldata}]`, used to generate the HTML. |
| `annotate.js` | Decodes `calldata.json` + `description.txt` → `proposal_13.html` (and computes the proposalId). |
| `proposal_13.html` | Self-contained annotated breakdown: copy-paste `propose()` arrays, decoded selectors/args/addresses, raw calldata per entry, proposalId. |

## Regenerate (only if addresses/description change)

```bash
forge script scripts/proposals/proposal_13/Proposal13Housekeeping.s.sol:Proposal13Housekeeping > /tmp/run.txt
# re-extract calldata.json from the run output, then:
node scripts/proposals/proposal_13/annotate.js "Proposal 13 — cross-chain housekeeping"
```

## Testing

### L1 — Forge fork test

[`test/proposals/Proposal13Housekeeping.t.sol`](../../../test/proposals/Proposal13Housekeeping.t.sol),
4 tests against a mainnet fork:

- `test_preconditions` — GuardCM owned by the Timelock, Mode route unset, Optimism route populated as
  a positive control, both bridge entrypoints have code;
- `test_L1_fullGovernanceLifecycle` — propose → vote → queue → execute through the live GovernorOLAS;
  Mode route set, Optimism route undisturbed, and **both** bridged entries observed dispatching
  (`SentMessage` from the Mode L1CDM to the Mode mediator; `StateSynced` from the FxStateSender to
  FxChild carrying `rootSender == Timelock` and `receiver == FxGovernorTunnel`).
  `execute()` measured at **2,548,065 gas** against the EIP-7825 cap of 16,777,216;
- `test_L1_fullProposal_executesAsTimelock` — fast path executing the batch directly as the Timelock;
- `test_proposalIdMatchesCommittedDescription` — pins the descriptionHash and proposalId so a drifted
  description cannot be submitted by accident.

```bash
ETH_RPC=<mainnet rpc> forge test --match-contract Proposal13HousekeepingTest -vvv
```

### L2 — destination-chain validation

The repo convention is Tenderly for bridged effects. That works for Polygon:

| | |
|---|---|
| simulation | `processMessageFromRoot(1, Timelock, packed)` sent from FxChild to the FxGovernorTunnel |
| status | success, 67,430 gas |
| state diff | `ServiceRegistryL2.mapMultisigs[0xa749f605…]` **`true` → `false`** |
| event | `MessageReceived(stateId=1, rootMessageSender=0x3c1ff68f…)` |

**Tenderly cannot simulate Mode.** Chain 34443 is absent from Tenderly's public-networks list and
`/simulate` returns HTTP 500 for it. Rather than validate one leg more weakly than the other, both
legs are additionally covered by fork tests in
[`test/proposals/Proposal13L2Legs.t.sol`](../../../test/proposals/Proposal13L2Legs.t.sol), which
replay the proposal's own packed buffers on a fork of each destination chain:

- `Proposal13ModeLegTest` — V1 de-allowlisted, **`implementationsCheck()` still `true`**, and the
  implementation behind Mode's 7 live proxies still verifies; plus a negative test that a foreign L1
  origin is rejected;
- `Proposal13PolygonLegTest` — PolySafe creator de-whitelisted, `GnosisSafeMultisig` untouched; plus
  the same negative test for a foreign root sender.

```bash
MODE_RPC=https://mainnet.mode.network forge test --match-contract Proposal13ModeLegTest -vvv
POLYGON_RPC=<polygon rpc>              forge test --match-contract Proposal13PolygonLegTest -vvv
```

All 8 tests pass.
