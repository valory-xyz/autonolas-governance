# Proposal 20 — validation record

Run 2026-11-26. `forge 1.5.1`, solc 0.8.30 (profile default). The CI workflow excludes
`test/proposals/*`, so these focused results are retained here with the proposal artifacts.

## Identity (4-way agreement)

| Source | proposalId | descriptionHash |
|---|---|---|
| Forge builder `Proposal20.run()` | `0x054aae970098f66ac399a88faf6f5181848ed56798c5bdb3a728160640a6ca59` | `0xc40673405bffa67856fedaeaa6728fa7526bdc161666d8a7f1d6a7426dc888f0` |
| `annotate.js` (decodes `calldata.json`) | same | same |
| `Proposal20Artifacts` (recomputed from committed artifacts) | same | same |
| committed `README.md` / `proposal_20.html` | same | same |

`total ETH value = 0 wei`, 3 entries.

## Automated artifact check (no RPC)

```
forge test --match-contract Proposal20Artifacts -vv
[PASS] test_artifacts_match_builder()  — calldata.json + description.txt == builder; proposalId/descHash == committed
```

HTML regeneration is byte-identical to the committed file:
```
node scripts/proposals/proposal_20/annotate.js "Proposal 20 — protocol maintenance"
git diff --exit-code scripts/proposals/proposal_20/proposal_20.html   # clean
```

## Fork test

| Test | Fork | Pinned block | Block hash | Result |
|---|---|---|---|---|
| `Proposal20ForkL1` | Ethereum | `26500400` | `0x71ee2791057c8793db1a55b6d3644c6867798858164b0e230bde635b4e51f4d7` | PASS |

Block is pinned in the test (override with `ETH_FORK_BLOCK`).

```
ETH_RPC_URL=<rpc> forge test --match-contract Proposal20ForkL1 -vv
[PASS] test_execute_L1()
  pre:  Tokenomics.dispenser()=0x5650300f… ; Treasury.dispenser()=0x5650300f… ; proxy.paused()=2
  post: Tokenomics.dispenser()=0x78Bd94F4… ; Treasury.dispenser()=0x78Bd94F4… ; proxy.paused()=0
  old Dispenser withdrawToAccount(): reverts (no longer the Treasury manager)
```
