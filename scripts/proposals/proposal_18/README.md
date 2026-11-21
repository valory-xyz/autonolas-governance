# Proposal 18 — protocol maintenance

Three Governor actions, all **value 0** (no prefund required).

| # | Chain | Target | Call |
|---|---|---|---|
| a | Ethereum (direct) | Dispenser `0x5650300fCBab43A0D7D02F8Cb5d0f039402593f0` | `setPauseState(2)` — pause staking-incentive distribution |
| b | Ethereum (direct) | GuardCM `0xC0b146D61e2A2C17E024477E01978D1Fcf598c6B` | `setTargetSelectorChainIds([0x78Bd94F4…], [pause()], [1], [true])` — allow the community-multisig guard to call `pause()` on the Dispenser proxy `0x78Bd94F4…` |
| c | Celo (bridged, OP-stack) | `ServiceRegistryL2 0xE3607b00E75f6405248323A9417ff6b39B244b50`, via Celo L1 messenger `0x1AC1181f…` → mediator `0xC14E191A…` | `changeMultisigPermission(0x63e66d7ad413…4bd1b, false)` — revoke a superseded GnosisSafe service-creation wrapper |

**Pre-computed proposalId:** `0x247593f31ea98cbc5473a694ee205a421855fad2f5d06532145e1381e59fa64b`
**descriptionHash:** `0x7a8b8025542da8e0b2da23ceaced58a3de156d54e5375dc512d3269db0c53881`
**Total ETH value:** `0` wei

## Reproduce

```bash
forge script scripts/proposals/proposal_18/Proposal18.s.sol:Proposal18 --sig "run()"
```
Emits the three `target / value / calldata` entries, the descriptionHash and the proposalId (matches the live
`GovernorOLAS.hashProposal(targets, values, calldatas, descriptionHash)`).

## Fork tests

```bash
ETH_RPC_URL=<rpc>  forge test --match-contract Proposal18ForkL1 -vv   # executes a+b+c as the Timelock; asserts pause()==2 and the guard pause() row
CELO_RPC_URL=<rpc> forge test --match-contract Proposal18Celo   -vv   # simulates the Celo delivery; asserts the wrapper revoke + gas (32,826) < OP_MIN_GAS (2,000,000)
```

## Notes
- GuardCM is granted the pause-only `pause()` selector (not `setPauseState`), so the CM can pause but not unpause a DAO-set pause.
- The Celo leg forwards 2,000,000 gas for a single ~33k-gas call — ample margin.
- `description.txt` carries the Autonolas DAO Constitution reference.
