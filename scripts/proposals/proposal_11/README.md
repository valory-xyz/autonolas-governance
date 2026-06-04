# Proposal 11 — Olas Governance & GuardCM activation

Completes the on-chain adoption of the updated **GovernorOLAS** and **GuardCM** deployed in
[PR #199](https://github.com/valory-xyz/autonolas-governance/pull/199), and bundles two related
protocol upgrades. Submitted via `propose()` on the **OLD** GovernorOLAS
(`0x8E84B5055492901988B831817e4Ace5275A3b401`), which still holds the Timelock roles. 16 entries,
all `values` = 0; every call is executed by the Timelock.

**Pre-computed proposalId:**
`112894799210697811565600237130962419038093907471146647660799369436721952152939`
(verified equal to on-chain `GovernorOLAS.hashProposal(...)`).

## What it does

| Part | Action | Target(s) |
|---|---|---|
| A (8 calls) | Migrate Timelock `ADMIN`/`PROPOSER`/`EXECUTOR`/`CANCELLER` roles old → new GovernorOLAS | Timelock |
| B (4 calls) | Configure new GuardCM bridge mediators + L2 verifiers (Gnosis, Polygon, Arbitrum, Optimism, Base, Celo — **Mode excluded**) | new GuardCM |
| C (1 call) | Set GuardCM CM allowlist: 16 (target, selector, chainId) entries — Treasury `pause()`/`drainServiceSlashedFunds()`, Depository `close(uint256[])`, ServiceRegistry(L2)/ServiceRegistryTokenUtility `drain()`/`drain(address)` on L1 + 6 L2s | new GuardCM |
| D (1 call) | Swap the CM guard to the new GuardCM via the Timelock Safe-module (`execTransactionFromModule` → `setGuard`) | Community Multisig |
| E (1 call) | Register new Celo BalanceTrackers on the Celo MechMarketplace (bridged via Celo L1CrossDomainMessenger) | Celo L1CrossDomainMessenger |
| F (1 call) | Upgrade Tokenomics implementation to v1.4.3 (`changeTokenomicsImplementation`) | TokenomicsProxy |

All addresses were verified on-chain (live Depository = `0xfF86…0C81`; the `0x52A0…` deploy is
decommissioned). See [`docs/activation_checklist_proposal_11.md`](../../../docs/activation_checklist_proposal_11.md)
for the full verified address matrix and rationale.

## Files

| File | Purpose |
|---|---|
| `Proposal11Activation.s.sol` | Forge builder — single source of truth for the 16 `(target, value, calldata)` entries and the `DESCRIPTION`. `forge script … :Proposal11Activation` prints the arrays. |
| `description.txt` | Canonical proposal description (matches the builder's `DESCRIPTION` byte-for-byte; the proposalId is computed from it). |
| `calldata.json` | The builder's emitted `[{index,target,value,calldata}]`, used to generate the HTML. |
| `annotate.js` | Decodes `calldata.json` + `description.txt` → the annotated `proposal_11.html` (and computes the proposalId). |
| `proposal_11.html` | Self-contained annotated breakdown: copy-paste `propose()` arrays, decoded selectors/args/addresses, collapsible nested calls, raw calldata per entry, proposalId. |

## Regenerate (only if addresses/description change)

```bash
forge script scripts/proposals/proposal_11/Proposal11Activation.s.sol:Proposal11Activation > /tmp/run.txt
# re-extract calldata.json from the run output, then:
node scripts/proposals/proposal_11/annotate.js
```

## Testing

**L1 (Forge fork test):** [`test/proposals/Proposal11Activation.t.sol`](../../../test/proposals/Proposal11Activation.t.sol)
executes the full 16-call batch as the Timelock against a mainnet fork and asserts every effect
(roles migrated, guard configured + swapped, Tokenomics impl upgraded, Celo `sendMessage` enqueued).

```bash
forge test --fork-url $MAINNET_RPC --match-contract Proposal11Activation -vvv
```

**L2 (bridged) — part E:** the Celo `setPaymentTypeBalanceTrackers` effect lands on Celo and is not
observable on a mainnet fork. Validate it with a Tenderly simulation on Celo of
`OptimismMessenger.processMessageFromSource(<packed payload>)` with `xDomainMessageSender` = the
mainnet Timelock. The exact packed payload is the decoded `_message` shown under entry [14] in the HTML.
