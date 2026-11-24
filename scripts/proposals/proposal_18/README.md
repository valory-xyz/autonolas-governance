# Proposal 18 — protocol maintenance

Three Governor actions, all **value 0** (no prefund required).

| # | Chain | Target | Call |
|---|---|---|---|
| a | Ethereum (direct) | Dispenser `0x5650300fCBab43A0D7D02F8Cb5d0f039402593f0` | `setPauseState(2)` — pause staking-incentive distribution |
| b | Ethereum (direct) | GuardCM `0xC0b146D61e2A2C17E024477E01978D1Fcf598c6B` | `setTargetSelectorChainIds(...)` — one atomic two-row update: **grant** the community-multisig guard `pause()` on the Dispenser proxy `0x78Bd94F4…` (chainId 1), and **revoke** its `setPauseState(uint8)` on the Dispenser `0x5650300f…` (chainId 1) |
| c | Celo (bridged, OP-stack) | `ServiceRegistryL2 0xE3607b00E75f6405248323A9417ff6b39B244b50`, via Celo L1 messenger `0x1AC1181f…` → mediator `0xC14E191A…` | `changeMultisigPermission(0x63e66d7ad413…4bd1b, false)` — revoke a superseded GnosisSafe service-creation wrapper |

**Pre-computed proposalId:** `0xc672870b3758789a7f404c384c19e2863285db95ec14c3f81af3e431a97ae7ea`
**descriptionHash:** `0x47d5bcb3a51d332ca4c08bc94f8d297746a50f71adb7459881dd055bd12b2a7e`
**Total ETH value:** `0` wei

## Reproduce & verify

```bash
# 1) Build: emits the three target/value/calldata entries, descriptionHash and proposalId
forge script scripts/proposals/proposal_18/Proposal18.s.sol:Proposal18 --sig "run()"

# 2) Assert the committed artifacts AGREE with the builder (no RPC): calldata.json + description.txt ==
#    builder (same entry count, so an appended action is caught), and the recomputed
#    proposalId/descriptionHash == the committed constants
forge test --match-contract Proposal18Artifacts -vv

# 3) Regenerate the decoded HTML from calldata.json and confirm it is byte-identical to the committed file
node scripts/proposals/proposal_18/annotate.js "Proposal 18 — protocol maintenance"
git diff --exit-code scripts/proposals/proposal_18/proposal_18.html
```

`run()` and `annotate.js` both print the proposalId, and it matches the live
`GovernorOLAS.hashProposal(targets, values, calldatas, descriptionHash)`.

## Fork tests

```bash
ETH_RPC_URL=<rpc>  forge test --match-contract Proposal18ForkL1 -vv   # executes a+b+c as the Timelock
CELO_RPC_URL=<rpc> forge test --match-contract Proposal18Celo   -vv   # simulates the Celo delivery
```

- **`Proposal18ForkL1`** asserts, pre→post: Dispenser `paused() 0 → 2`; GuardCM `pause()` on the new proxy `false → true`; GuardCM `setPauseState(uint8)` on the old Dispenser `true → false` (the revoke).
- **`Proposal18Celo`** validates the outer route+selector of entry 2 (target is the Celo L1 messenger, selector is `sendMessage`), then delivers the builder's `inner` bytes **unchanged** (selector included, so a wrong inner selector reverts) with the forwarded-gas budget read from the same entry, and asserts the wrapper permission is revoked and that delivery (≈33k gas) fits the budget (2,000,000). Nothing is hardcoded or re-wrapped.

Pinned fork blocks, hashes, commands and results are in [`TEST_RECORD.md`](./TEST_RECORD.md). (The CI workflow excludes `test/proposals/*`, so these results travel with the proposal.)

### Simulation boundaries

- `Proposal18ForkL1` executes the three entries while impersonating the Timelock. It validates the target calls and the resulting on-chain state; it does **not** exercise the GovernorOLAS propose → vote → queue flow or the Timelock min-delay. The end-to-end `execute()` fork-simulation through the Governor and Timelock is run at submission time (proposal checklist, step 4).
- `Proposal18Celo` models OP-stack delivery by pranking the L2 cross-domain messenger predeploy `0x42…07` and mocking `xDomainMessageSender() == Timelock`. It does **not** exercise real L1→L2 message passing (relay/finalization); it confirms that the delivered batch, exactly as built, executes within the forwarded gas budget.

## Notes
- GuardCM row 0 grants the pause-only `pause()` selector (not `setPauseState`) on the new proxy, so the community multisig can pause but not unpause. Row 1 removes the community multisig's prior `setPauseState(uint8)` permission on the old Dispenser, in the **same** call, so it cannot reopen a pause set by this proposal. Removing the permission does not cancel any community-multisig operation already prepared against that selector — that is verified separately before execution.
- The Celo leg forwards 2,000,000 gas for a single ~33k-gas call — ample margin.
- `description.txt` carries the Autonolas DAO Constitution reference and must match the builder constant byte-for-byte (asserted by `Proposal18Artifacts`).
