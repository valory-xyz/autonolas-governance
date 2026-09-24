# Area 0 — on-chain inventory, Ethereum mainnet

**Evidence packaging:** this report describes the original pinned collection. Published links now lead to the [compact evidence index](../EVIDENCE.md) or original sources. Raw RPC responses, generated JSON and verbose test logs remain local/ignored; [reproduction instructions](../README.md#4-reproduction) explain how to recollect them.


Window: blocks 24577960 (first block after the baseline commit, 2026-03-03T15:55:58Z) to 26032401 (head at collection, 2026-09-22). Live-state reads are pinned at block 26032401.

Reproduce from the repository root (read-only; default RPC is the public Tenderly gateway):

```sh
node audits/2026-09-22-governance-review/onchain/collect_logs.js
node audits/2026-09-22-governance-review/onchain/decode_logs.js
```

Outputs: [Evidence references: raw logs](../EVIDENCE.md#proposals), [Evidence references: decoded timeline](../EVIDENCE.md#proposals). Addresses covered: Timelock, GovernorOne, GovernorTwo, current Governor, both GuardCM instances, CM Safe (all events), and Treasury (`OwnerUpdated` only). L2 chains, the veto stack, and other governed targets are **not** covered yet.

## Current review selection

The proposal review now selects proposals created on or after May 1, 2026 (00:00 Europe/Rome), through September 22. The raw collection below retains its original, broader March–September coverage; its aggregate counts describe that collection, not a newly filtered run. All proposals listed in the table below were created after May 1. Related actions and earlier state are used as context where needed, rather than as an exhaustive independent activity review.

## Scope limit

This is Ethereum-only. Bridged actions are counted when the L1 message was sent, not when it executed on L2; the L2 legs (area 4) still need to be checked per chain.

## Offline reconciliation of the saved evidence

The May-onward proposal selection and artifact comparison can be reproduced with `python3 audits/2026-09-22-governance-review/onchain/check_point0.py`; results are saved in [Evidence references: point0_reconciliation.json](../EVIDENCE.md#proposals). This check uses saved logs and local artifacts, not new RPC calls. It finds 12 proposals: nine with execution events, one with a cancellation event, and two whose ended voting periods have zero For votes and positive Against votes (Defeated inferred from those observations). Proposals 12–16 match both the exact description and ordered target/value/calldata lists. Proposal 11 is a related but different artifact. No matching artifact is found among the scanned proposal folders for the other six proposals. Lack of a match here does not establish absence from every repository.

## Summary

- **The collected Timelock calls reconcile.** Matching operation IDs and call indices gives 148 scheduled calls = 107 executed calls + 41 calls belonging to the cancelled operation. No scheduled call in this collected set remains unmatched. This does not rule out pending operations scheduled before the collection window.
- **No owner-execution events were collected from the CM Safe**: zero `ExecutionSuccess` or `ExecutionFailure`. Its collected execution event is the guard swap through the Timelock module (`ExecutionFromModuleSuccess`, tx `0x1ea31f99…`). This provides no evidence of completed owner-authorized CM actions in the covered logs. Reverted attempts, including guard rejections, leave no retained event logs and are not excluded by this collection. The Timelock is an enabled module on the CM, so governance can act through the CM without passing through the guard. This fits the design (it was used for the swap), but it must be part of the powers model in area 2.
- **12 proposals.** Five match the repository byte-for-byte on the description and ordered target/value/calldata lists (12–16). One matches in substance but was changed before submission (11). Four executed or cancelled proposals have no repository artifact. Two came from outside proposers and were defeated.

## How the proposal summary is obtained

This section separates **proposal identity**, **artifact matching**, **action interpretation**, and **outcome evidence**. The summaries are manually written from the saved on-chain descriptions, recognizable calls, and repository documents. They are not a complete independent validation of every call's meaning or effect.

1. **Collect.** [collect_logs.js](collect_logs.js) queries Ethereum `eth_getLogs` for the recorded addresses and block range, saving [Evidence references: raw_logs.json](../EVIDENCE.md#proposals).
2. **Decode.** [decode_logs.js](decode_logs.js) uses the repository ABIs to decode events, retrieves block timestamps, and saves [Evidence references: timeline.json](../EVIDENCE.md#proposals). Despite its opening “offline” comment, this step makes RPC requests for timestamps and any selected Safe transaction inputs. `ProposalCreated` supplies the proposal ID, proposer, description, ordered targets, values, signatures, and calldatas.
3. **Select and join.** [check_point0.py](check_point0.py) runs offline, selects proposals created from May 1, and joins lifecycle/vote events using **Governor + proposal ID**. Full IDs, creation transactions, action counts, and comparison results are saved in [Evidence references: point0_reconciliation.json](../EVIDENCE.md#proposals). Dates displayed below are UTC dates from the saved timestamps; the selection boundary is midnight Europe/Rome.
4. **Match artifacts.** Compare the description and ordered target/value/calldata lists against local `scripts/proposals/proposal_*/description.txt` and `calldata.json`. The script uses exact description or majority same-position call overlap to identify candidate artifacts; only the explicit equality checks establish an exact match. Non-empty Bravo signatures would require additional normalization; the script asserts they are empty for these proposals.
5. **Explain actions.** Paraphrase the on-chain description, checking available function selectors/arguments and repository documentation. Full semantic validation additionally requires the ABI and code actually deployed at each target, recursive decoding of bridge payloads, and resulting-state checks. A description, a recognized selector, and byte equality with an artifact are distinct evidence levels.

### How proposal labels are assigned

| Label in the summary | Association method | Limit |
|---|---|---|
| Proposals 12–16 | Exact description and ordered target/value/calldata match with the corresponding repository folder. | Establishes artifact fidelity, not correctness or destination-chain completion. |
| Proposal 11 | Activation description and substantial same-position call overlap: 15 of the artifact's 16 calls match their on-chain positions. | A related partial artifact, not the identical submitted proposal; see the composition note below. |
| Date and descriptive label | A human-readable label based on the on-chain description/calls where the scan found no matching artifact. | Not an official proposal number, and not proof that no artifact exists in another repository. |

### How outcomes are established

| Recorded outcome | Count | Evidence |
|---|---:|---|
| Executed on Ethereum | 9 | Matching `ProposalExecuted` event. The displayed execution date is its block timestamp. |
| Cancelled | 1 | Matching `ProposalCanceled` event. |
| Defeated (inferred) | 2 | `endBlock` precedes the collection block, with zero For votes and positive Against votes in the saved events. This offline check does not call `state(proposalId)`. |

“Executed” does not establish L2 message delivery, destination execution, or completion of a return message. State and contract-type claims need their own reads; they are not established by the event reconciliation alone. The saved dataset is not an independent proof of RPC completeness.

## Proposal action summary

Each label links to its creation transaction for identification. Full proposal IDs and original descriptions remain in the saved JSON evidence. The **action summaries are primarily description-derived, with partial calldata validation**; all nested cross-chain calls have not been independently checked against deployed destination implementations. For the two transfer proposals, the summaries follow the identified calls rather than repeating their potentially misleading titles.

| Proposal / created (2026) | Action summary | Recorded outcome | Repository association |
|---|---|---|---|
| [Marketplace fees](https://etherscan.io/tx/0xbe798fec1b45f2783ec2da48c0cf651f08203de7e0b9a897ae84a89a5942b1a2) · 2026-06-09 | Sets the MechMarketplace fee from 0% to 15% on Ethereum and six L2s; keeps the minimum/maximum response-timeout limits at 60/300 seconds. | Executed 2026-06-15 | No match in scanned folders |
| [Proposal 11 — activation](https://etherscan.io/tx/0xc787e567de0fa97b3e95f49267ec91c7662a941f2b021cb55f4442864c91f0d4) · 2026-06-10 | Activates the new Governor and GuardCM, migrates Timelock roles, configures bridge verification and CM permissions, and swaps the Safe guard. Also bundles Celo BalanceTracker configuration and Tokenomics/ServiceManager upgrades. | Executed 2026-06-15 | proposal_11 — partial/different |
| [Combined maintenance](https://etherscan.io/tx/0xa2b65cbf00e289c43f3757f68fa9a1040f035e0803af9ba5ed9f258f95c633a5) · 2026-06-23 | Proposes retiring same-address multisig implementations, removing staking nominees, and extending CM emergency permissions. Related work appears in the subsequent July proposals; these are revised proposals, not an assumed byte-identical split. | Cancelled 2026-07-06 | No match in scanned folders |
| [Security/configuration changes](https://etherscan.io/tx/0xd543cd06415529a021ef30be0124af31f318ed61adb604e0aae92647941184ac) · 2026-07-06 | Disables same-address multisig adoption paths, extends CM pause/drain permissions, and disables factories for creating new mechs paid in OLAS. | Executed 2026-07-14 | No match in scanned folders |
| [Nominee cleanup](https://etherscan.io/tx/0xdbf70e9865084431138e0bb91b7904bd81014abcd8693203cfb46d695184efd2) · 2026-07-07 | Removes 32 retired staking nominees from VoteWeighting. | Executed 2026-07-17 | No match in scanned folders |
| [Proposal 12 — nominee cleanup](https://etherscan.io/tx/0x022dc3ae2563986b3d49ab22823419282f29a562f8a0b3bf4e6a9b9791dbe467) · 2026-07-24 | Removes another 20 legacy staking nominees from VoteWeighting. | Executed 2026-08-01 | proposal_12 — exact |
| [Proposal 13 — housekeeping](https://etherscan.io/tx/0x5f0619287426cea54134f99ae7092fe1c3c7179607a8690e4dca49e74c7566cd) · 2026-09-01 | Configures the Mode route in GuardCM, removes an old Mode staking implementation from its allowlist, and retires the Polygon PolySafe creator. | Executed 2026-09-08 | proposal_13 — exact |
| [Proposal 14 — withheld balances](https://etherscan.io/tx/0x7b3be2afc8018ef3591f05938afa4c49b0f3b96c8866272b9d564318bc6439f9) · 2026-09-05 | Requests that seven L2s report retained staking-incentive balances to Ethereum so they can offset future transfers. Does not transfer the retained OLAS back; completion requires L2 execution and L1 accounting credit. | Executed 2026-09-12 | proposal_14 — exact |
| [Treasury ownership transfer](https://etherscan.io/tx/0xe435eed3f2fe2be35a663c8f779738023f9e2cb0ae4f576fdf4d1f63dd09b524) · 2026-09-05 | Calls Treasury.changeOwner with recipient 0x7b8e…561d. The description calls it a “Safe updater”; the prior investigation identifies an EOA. The contract-type claim is separate from decoding the recipient. | Defeated (inferred) | No match in scanned folders |
| [Treasury and minter transfer](https://etherscan.io/tx/0xe0dc8a1ff4f5319c9d9dbb411f8b1387ddd53d96c23f6a81e3f5e0040a53cccc) · 2026-09-06 | Calls Treasury.changeOwner and OLAS.changeMinter with the proposer as recipient, despite the description referring to a Safe-module upgrade. | Defeated (inferred) | No match in scanned folders |
| [Proposal 15 — governance parameters](https://etherscan.io/tx/0x901d039d8afb34798362e373cf0d4243db63a05923cfc207bfcd2aafe53f1a26) · 2026-09-06 | Raises the proposal threshold from 5,000 to 250,000 veOLAS units and the quorum numerator from 3 to 10 (denominator 100). | Executed 2026-09-13 | proposal_15 — exact |
| [Proposal 16 — Robinhood integration](https://etherscan.io/tx/0x6f709954629c247ce5e7b8ead8d4c0f263758958cfcff188e89b85c6829ae28a) · 2026-09-11 | Registers the Robinhood Chain incentive deposit processor and GuardCM bridge route, and allowlists specified CM pause/drain actions. Unpause is excluded. | Executed 2026-09-18 | proposal_16 — exact |

For the fee proposal, “keeps the response-timeout limits” means the submitted call is `changeMarketplaceParams(1500, 60, 300)`: the stated fee changes to 15%, while the description says the timeout bounds remain 60 seconds and 300 seconds. These bounds are not a guarantee that a response arrives within that interval. Independently establishing that the values were unchanged requires a pre-execution state read.

**Reproduction boundary.** Running `python3 audits/2026-09-22-governance-review/onchain/check_point0.py` reproduces proposal counts, lifecycle associations, artifact comparisons, and Timelock operation reconciliation from the saved data. It does not generate or independently validate these narrative action summaries. The proposal artifacts are read from the local checkout; changes to them can change comparison results. No new chain queries or full destination-call validation were performed to add this section.

All official proposals share one proposer (`0x34471096…0039`, a contract).

### Proposal 11: executed version differs from the repository

**Classification clarified during review:** the user identifies the extra calls as actions from other repositories, including registries. A combined cross-repository proposal differing from this repository's partial artifact is not, by itself, a contract or governance security issue. Treat this as a scope/composition note; link the relevant external artifacts when reviewing those actions. Their provenance has not been independently reconciled by the offline comparison script.

The on-chain description adds section **(G)**: upgrades of the ServiceManager implementation on Ethereum and six L2s. The executed proposal has 22 actions; `calldata.json` has 16. On-chain actions 16–21 are not in the repository, and action 14 (the Celo message) has different calldata. The repository builder, calldata and `Proposal11Activation.t.sol` therefore do not reproduce what was executed. This does not prove the executed actions are wrong, but they are unreviewed from this repository's point of view.

### Two defeated proposals targeting Treasury and the OLAS minter

| Proposal | Proposer | Calls |
|---|---|---|
| "Owner migration: transfer treasury ownership from old timelock to Safe updater" | EOA `0xD4f8…5451` | Treasury `changeOwner(0x7b8e…561d)`, an EOA with nonce 3 |
| "Treasury and token controller upgrade to Safe v2.1 module" | EOA `0x56F0…CEf5` (≈5.1k, just above the old 5k threshold) | Treasury `changeOwner(proposer)`; OLAS `changeMinter(proposer)` |

Both descriptions misdescribe their effect. Each was defeated: there were no votes in favour, the Against totals exceeded the quorum in force at the time, and the proposers did not vote. Voter identities and holder voting capacity are part of the voting-power follow-up and are not recorded here. Two facts show what was at stake: OLAS `minter()` is the Treasury, and Treasury `owner()` is the Timelock. These are the concrete events behind proposal 15. With the new 250k threshold, neither proposer could create a proposal today.

## Live state at block 26032401

For a separately collected, slightly later state snapshot at block **26032428**, the point-1 [offline verifier](../point-1/verify_saved_roles.cjs) decodes cached `eth_call` responses for role membership and parameters and checks them against the saved snapshot. Its [Evidence references: results](../EVIDENCE.md#roles-and-recovery) link every checked value to its raw RPC response. This verifies named/window-discovered accounts, not an exhaustive role-holder enumeration from deployment. It does not re-query a provider.

| Item | Value |
|---|---|
| Timelock `PROPOSER_ROLE` | Governor, CM |
| Timelock `EXECUTOR_ROLE` | Governor, CM (not open to `address(0)`) |
| Timelock `CANCELLER_ROLE` | Governor only |
| Timelock `TIMELOCK_ADMIN_ROLE` | Governor, Timelock |
| Timelock `getMinDelay()` | **0**; the effective delay is Governor `governorDelay` = 157092 seconds (43 h 38 min 12 s) |
| GovernorTwo `0x8E84…` roles | none (revoked 06-15) |
| Governor params | threshold 250,000; quorum 10; voting delay 13091; period 19636 |
| CM Safe | v1.3.0, threshold 5; guard = new GuardCM `0xC0b1…8c6B` |
| New GuardCM | governor = current Governor; owner = Timelock; `paused` = 1 (active) |
| Old GuardCM `0x7bB7…` | governor = GovernorTwo; owner = Timelock; not the CM guard |
| Treasury `owner()` | Timelock |
| OLAS `owner()` / `minter()` | Timelock / Treasury |

## Follow-ups within the agreed review scope

- **Main governance:** use the later [point-1 results](../point-1/README.md) for role and timing checks already performed. Voting-power distribution and quorum coverage remain in the current checklist; historical questions here do not reopen completed checks.
- **CM changes:** verify governance-relevant effects of the activation and changed route/permission proposals. Retain the July Dispenser permission, Celo and new/changed destination paths as specific questions. Reuse applicable coverage for unchanged behaviour under the [CM review boundary](../README.md#cm-review-boundary).
- **Proposal composition:** retain the proposal-11 cross-repository composition note. Locate or reconstruct additional payloads only where needed to understand in-scope governance authority or changed effects; this is not a standalone review of external business logic or unrelated activity.
- **Veto:** deployment and activation remain to be established in the separate veto review; absence from this inventory does not prove non-deployment.
- **VoteWeighting:** retain both nominee-removal batches in the accounting review: 32 on July 17 and 20 on August 1, totalling 52. The reduced CM scope does not remove this follow-up.

L1 execution still does not prove destination execution. Paths not independently checked must remain labelled as such; deferring unchanged integrations is a scope choice, not confirmation that they work.
