# Proposal 20 — protocol maintenance

Three Governor actions, all on Ethereum, all **value 0** (no prefund required), all direct Timelock calls.

| # | Target | Call |
|---|---|---|
| a | Tokenomics `0xc096362fa6f4A4B1a9ea68b1043416f3381ce300` | `changeManagers(0, 0, 0x78Bd94F4…D83D)` — set the Tokenomics **dispenser** manager to the Dispenser proxy (the zero `treasury`/`depository` args leave those managers unchanged) |
| b | Treasury `0xa0DA53447C0f6C4987964d8463da7e6628B30f82` | `changeManagers(0, 0, 0x78Bd94F4…D83D)` — set the Treasury **dispenser** manager to the same Dispenser proxy (the zero `tokenomics`/`depository` args leave those unchanged). This authorises the proxy for `withdrawToAccount` |
| c | Dispenser proxy `0x78Bd94F48CAe623CC74828eCbFEBE3bDF428D83D` | `setPauseState(0)` — set the pause state to **Unpaused** |

**Pre-computed proposalId:** `0x054aae970098f66ac399a88faf6f5181848ed56798c5bdb3a728160640a6ca59`
**descriptionHash:** `0xc40673405bffa67856fedaeaa6728fa7526bdc161666d8a7f1d6a7426dc888f0`
**Total ETH value:** `0` wei

## Reproduce & verify

```bash
# 1) Build: emits the three target/value/calldata entries, descriptionHash and proposalId
forge script scripts/proposals/proposal_20/Proposal20.s.sol:Proposal20 --sig "run()"

# 2) Assert the committed artifacts AGREE with the builder (no RPC): calldata.json + description.txt ==
#    builder (same entry count, so an appended action is caught), and the recomputed
#    proposalId/descriptionHash == the committed constants
forge test --match-contract Proposal20Artifacts -vv

# 3) Regenerate the decoded HTML from calldata.json and confirm it is byte-identical to the committed file
node scripts/proposals/proposal_20/annotate.js "Proposal 20 — protocol maintenance"
git diff --exit-code scripts/proposals/proposal_20/proposal_20.html
```

`run()` and `annotate.js` both print the proposalId, and it matches the live
`GovernorOLAS.hashProposal(targets, values, calldatas, descriptionHash)`.

## Fork test

```bash
ETH_RPC_URL=<rpc> forge test --match-contract Proposal20ForkL1 -vv   # executes a+b+c as the Timelock
```

- **`Proposal20ForkL1`** asserts, pre→post: Tokenomics `dispenser` `0x5650300f… → 0x78Bd94F4…`; Treasury `dispenser` `0x5650300f… → 0x78Bd94F4…`; the Dispenser proxy `paused() 2 → 0`. It then proves the **old** Dispenser can no longer pull from the Treasury (`withdrawToAccount` from the old Dispenser reverts, because `dispenser` is now the new proxy).

Pinned fork block, hash, command and result are in [`TEST_RECORD.md`](./TEST_RECORD.md). (The CI workflow excludes `test/proposals/*`, so these results travel with the proposal.)

### Simulation boundaries

- `Proposal20ForkL1` executes the three entries while impersonating the Timelock. It validates the target
  calls and the resulting on-chain state (both managers repointed, the proxy unpaused, the old Dispenser no
  longer authorised to withdraw from the Treasury). It does **not** exercise the GovernorOLAS propose → vote →
  queue flow or the Timelock min-delay — the end-to-end `execute()` fork-simulation through the Governor and
  Timelock is run at submission time (proposal checklist, step 4).
- It asserts the manager/authorisation and pause state transitions directly. A full dev-incentive claim and a
  staking-incentive settlement against the newly-active Dispenser proxy are exercised by that submission-time
  `execute()` simulation rather than re-staged here (both require live epoch/nominee state).

## Notes
- `changeManagers` on both Tokenomics and Treasury takes the dispenser as its **third** argument and skips any
  zero-address argument (`if (_x != address(0))`), so `changeManagers(0, 0, proxy)` updates **only** the
  dispenser and leaves the other managers untouched — verified against the deployed source.
- Entry (c) unpausing is accepted because the proxy's `voteWeighting` is already bound (it rejects
  `setPauseState` while `voteWeighting == 0`). Dev-incentive claims resume on execution; staking-incentive flow
  resumes once gauges are nominated and an epoch passes.
- `description.txt` carries the Autonolas DAO Constitution reference and must match the builder constant
  byte-for-byte (asserted by `Proposal20Artifacts`).
