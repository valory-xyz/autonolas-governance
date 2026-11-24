# Proposal 18 — validation record

Run 2026-11-24. `forge 1.5.1`, solc 0.8.30 (profile default). The CI workflow excludes
`test/proposals/*`, so these focused results are retained here with the proposal artifacts.

## Identity (4-way agreement)

| Source | proposalId | descriptionHash |
|---|---|---|
| Forge builder `Proposal18.run()` | `0xc672870b3758789a7f404c384c19e2863285db95ec14c3f81af3e431a97ae7ea` | `0x47d5bcb3a51d332ca4c08bc94f8d297746a50f71adb7459881dd055bd12b2a7e` |
| `annotate.js` (decodes `calldata.json`) | same | same |
| `Proposal18Artifacts` (recomputed from committed artifacts) | same | same |
| committed `README.md` / `proposal_18.html` | same | same |

`total ETH value = 0 wei`, 3 entries.

## Automated artifact check (no RPC)

```
forge test --match-contract Proposal18Artifacts -vv
[PASS] test_artifacts_match_builder()  — calldata.json + description.txt == builder; proposalId/descHash == committed
```

HTML regeneration is byte-identical to the committed file:
```
node scripts/proposals/proposal_18/annotate.js "Proposal 18 — protocol maintenance"
git diff --exit-code scripts/proposals/proposal_18/proposal_18.html   # clean
```

## Fork tests

| Test | Fork | Pinned block | Block hash | Result |
|---|---|---|---|---|
| `Proposal18ForkL1` | Ethereum | `26485290` | `0x3adc5f01088bbf48a82f0ef3b1dd0107b2aba0633dd9c3bdcc4f1b15929ef9ad` | PASS |
| `Proposal18Celo` | Celo | `83626048` | `0x54aa0bbab4d3ec8194ecf4031d612962b56dc61ae9dff56bbfa6a18955d0ad8b` | PASS |

Blocks are pinned in the tests (override with `ETH_FORK_BLOCK` / `CELO_FORK_BLOCK`).

```
ETH_RPC_URL=<rpc>  forge test --match-contract Proposal18ForkL1 -vv
[PASS] test_execute_L1()
  pre:  Dispenser.paused()=0 ; GuardCM[newProxy,pause(),1]=false ; GuardCM[oldDispenser,setPauseState,1]=true
  post: Dispenser.paused()=2 ; GuardCM[newProxy,pause(),1]=true  ; GuardCM[oldDispenser,setPauseState,1]=false

CELO_RPC_URL=<rpc> forge test --match-contract Proposal18Celo -vv
[PASS] test_celo_revoke_fromBuilder()
  wrapper mapMultisigs: true -> false
  celo delivery gas used: 32601 of forwarded budget: 2000000   (outer route+selector validated; builder `inner` bytes delivered unchanged)
```
