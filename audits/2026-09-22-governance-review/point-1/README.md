# Point 1 — main governance activation, powers, and parameters

**Evidence packaging:** this report describes the original pinned collection. Published links now lead to the [compact evidence index](../EVIDENCE.md) or original sources. Raw RPC responses, generated JSON and verbose test logs remain local/ignored; [reproduction instructions](../README.md#4-reproduction) explain how to recollect them.


Review snapshot: `93901ec315eb2b1d4683aab5615ef38b071228f8`. Tag baseline: `v1.2.5-post-external-audit`. Ethereum state pinned to **block 26,032,428**, hash `0x4676a14bf8236315a34cfd31f5c308ae66553b574a3ee701db2458f26e6e4fd6` ([pin.json](data/pin.json)), **2026-09-22 10:27:59 UTC**. The full hash in that file is authoritative.

## Results

**Follow-up:** [complete role history and lockout recovery](ROLES_AND_RECOVERY.md) extends the original checks with deployment-to-pin role enumeration, role-administration reads, CM module/heartbeat state, and nine passing recovery tests.

1. **Activation is confirmed, not merely documented.** The new Governor took over all four relevant Timelock roles and the CM Safe switched guards in the June 15 activation transaction. The old Governor lost those roles. The Treasury remains owned by the Timelock at all five sampled blocks.
2. **Proposal 15 executed on September 13.** Its committed description and both calls match the on-chain proposal exactly. The active threshold is 250,000 veOLAS units and quorum numerator is 10/100.
3. **The activation artifact is not the executed proposal.** The repository contains 16 calls; the executed proposal contains 22. Calls 0–13, covering role migration and guard configuration/swap, match. Call 14 differs, call 15 matches, and calls 16–21 are absent from the artifact. The on-chain description includes additional ServiceManager upgrades. This is a confirmed traceability gap, not proof that those upgrades were unauthorized or defective.
4. **Two known governance lockout conditions remain reproducible on deployed bytecode.** Raising Timelock `minDelay` above `governorDelay` blocks queueing a repair; setting the Governor's Timelock to zero is accepted and also blocks subsequent queueing. Both require an approved governance action. Neither condition is present at the pinned block.
5. **The documented CM recovery route for delay desynchronization is unavailable through the current allowlist.** `Timelock.updateDelay` is not allowlisted. The follow-up demonstrates pre-queued delay repair and CM recovery conditional on guard release. The configured heartbeat is unknown at the pin, so release is not established as immediately available.
6. **The parameter tests and explanatory artifacts have unresolved limitations.** Two of six existing proposal-15 tests fail against current mainnet because they assume the pre-execution state. A purported check of the new quorum reads the previous block's old quorum. These are validation/documentation issues, not evidence that the executed setters malfunctioned.

No permissionless theft or takeover exploit is established by this review. This is a bounded assessment of point 1; it does not close the broader CM/bridge review or the full independent on-chain inventory.

## Evidence and method

- [Chain collector](collect_chain.cjs): read-only RPC calls, explorer pagination, and block-pinned state. All raw RPC requests/responses are saved under `data/rpc`; explorer pages are under `data/explorer`.
- [PR collector](collect_prs.py): PRs #178, #187, #199, #200, #209, #232, #233, including review bodies. Inline review-thread comments are not included in this collection.
- [Contract/state enrichment](enrich_chain.cjs): verified source bundles, runtime bytecode, recovery allowlist checks, and proposal vote totals.
- [Offline reconciliation](analyze_evidence.cjs): independently recomputed proposal IDs, call-by-call artifact comparisons, and **130 decoded explorer events checked against successful RPC transaction receipts**.
- [Design text extraction](collect_design.py): the 66-page contract specification and three-page governance-process document. Text was reviewed; diagrams were not used as evidence.
- [Full role-history collector](collect_role_history.cjs), [Evidence references: reconstructed roles and recovery prerequisites](../EVIDENCE.md#roles-and-recovery), and [nine recovery fork tests](tests/GovernanceRecoveryReview.t.sol). See the [follow-up report](ROLES_AND_RECOVERY.md) for assumptions, successful output, and remaining operational requirements.
- [Five local mechanism tests](tests/GovernanceReview.t.sol) and [two tests of deployed contracts on a pinned local fork](tests/GovernanceLiveReview.t.sol). No transaction was broadcast.

The main Governor's **29 explorer-published source files match the checkout/dependencies byte-for-byte**. Its explorer runtime matches the runtime returned by RPC. Compiled executable bytecode also matches after excluding compiler-declared immutable slots and CBOR metadata; the live token address is independently checked. This does not claim full constructor-byte equality. Explorer verification reports Solidity **0.8.30**, optimizer **200 runs**, EVM **Prague**, runtime **20,479 bytes**. PR #209's body says 750 runs for the new Governor; that statement conflicts with the verified deployment metadata. The previous Governor used 750 runs.

The deployed Timelock is older than the current Timelock source: explorer metadata reports Solidity 0.8.15 and its constructor has three arguments. The two live-fork reproductions use this deployed Timelock rather than assuming the current source is identical.

## 1. What changed, why, and whether it is live

### Governor activation and delay separation

The original design allows governance to replace a non-upgradeable Governor through a vote, change governance parameters, and provide a separate trusted CM path. It also states that the CM cannot change Governor-sensitive parameters. See [governance-process text](../../../docs/Governance_process.pdf), pages 1–3, and [contract-specification text](../../../docs/Specs%20of%20governance%20contracts_v1.1.0.pdf), Governor/Timelock sections.

[PR #178](https://github.com/valory-xyz/autonolas-governance/pull/178), merged before the tag baseline, explicitly separates two delays: zero Timelock minimum delay for permitted CM actions, and a Governor-specific delay for voted proposals. The implementation therefore predates this review's source baseline, but its activation belongs to the reviewed operational changes. PR #178's historical “~4h” example must not be used as the actual deployed parameter.

[PR #199](https://github.com/valory-xyz/autonolas-governance/pull/199) records deployment separately from activation. [PR #200](https://github.com/valory-xyz/autonolas-governance/pull/200) prepares the activation, and [PR #209](https://github.com/valory-xyz/autonolas-governance/pull/209) records it as executed.

Actual activation: **June 15, 2026, 10:33:11 UTC**, block **25,322,326**, [transaction](https://etherscan.io/tx/0x1ea31f9979e39a288a09aadabb1db1e4e76a124bb9f825cb07b4829bb46b0168). The transaction calls the old Governor and succeeds. Before/after state is captured at blocks 25,322,325 and 25,322,326.

| Property | Before activation | After activation and at the pinned block |
|---|---|---|
| Governor holding Timelock ADMIN, PROPOSER, EXECUTOR, CANCELLER | `0x8E84…b401` | `0x060D…51E6` |
| Old Governor's four roles | All present | All absent |
| CM Safe guard | `0x7bB7…6f3a` | `0xC0b1…8c6B` |
| CM Timelock roles | PROPOSER, EXECUTOR | PROPOSER, EXECUTOR; no ADMIN/CANCELLER |
| Timelock as Safe module | Enabled | Enabled |
| Treasury owner | Timelock `0x3C1f…D95fE` | Same Timelock |
| Governor token | wveOLAS `0x4039…4B40` | Same wrapper |
| Timelock minimum delay | 0 seconds | 0 seconds |
| New Governor execution delay | Deployed but not yet authoritative: 157,092 seconds | Active: 157,092 seconds |

The earlier `0x34C8…3dd5` Governor, both guard addresses, and the zero address hold none of the four queried Timelock roles at the pinned block. The Timelock holds its own admin role. The subsequent [deployment-to-pin reconstruction](ROLES_AND_RECOVERY.md#1-who-actually-controls-the-timelock) replays 31 role events and checks membership and role administration at the pin. It finds no additional holder, subject to RPC log completeness and the deployed AccessControl event semantics.

Voting delay remains **13,091 blocks** and voting period **19,636 blocks**. These are block counts; `governorDelay` is seconds. The new execution delay is exactly **43 hours, 38 minutes, 12 seconds**. Converting voting blocks to days would require a block-time assumption and is not needed to establish the configuration.

### Proposal 15

Stated motivation: reduce access to proposal creation and raise the voting-power floor for passage after a Treasury-ownership-transfer proposal. This is a participation/security trade-off; it does not prevent a sufficiently funded proposer from submitting or passing proposals.

Actual execution: **September 13, 2026, 07:16:59 UTC**, block **25,966,959**, [transaction](https://etherscan.io/tx/0xe1d90f1cf0fa3c18c2e8328062689328e9ebbc4b50d093eebccc7668454e5d6f).

| Parameter | Block 25,966,958 | Block 25,966,959 and pinned block |
|---|---:|---:|
| Proposal threshold | 5,000 × 10¹⁸ | 250,000 × 10¹⁸ |
| Quorum numerator | 3 | 10 |
| Quorum denominator | 100 | 100 |
| Voting delay / voting period | 13,091 / 19,636 blocks | Unchanged |
| Governor delay | 157,092 seconds | Unchanged |

Both executed calls and the description match the committed artifacts. The proposal ID is `3563000702947626407249966116394330391891319244018918786718598572660765109424`.

Mechanisms must be distinguished:

- **Proposing:** uses the current threshold and the proposer's past voting power at the preceding block.
- **Quorum:** uses the numerator at the proposal snapshot. Already snapshotted proposals retain their old numerator; pending proposals whose snapshot falls after the change can use the new numerator.
- **Cancellation:** Bravo compares the proposer's preceding-block voting power to the **current**, uncheckpointed threshold. Raising the threshold can make an existing, even queued, proposal cancellable by anyone. The local behavioral test reproduces this. This is existing inherited behavior, not a new setter bug.
- **Governor-only settings:** Timelock identity alone is insufficient. OpenZeppelin's `onlyGovernance` also checks the authorized-call queue populated during Governor execution. The local test confirms that impersonating the Timelock alone cannot change the threshold. The current guard also does not allow the CM to schedule these settings calls.

The README's “Nothing in flight is affected” heading is too broad if read as covering the whole proposal. Its following quorum-specific explanation is narrower and correct for already snapshotted proposals. The immutable description uses that narrower wording.

### Treasury-control proposals and actual outcome

Two proposals were discovered, not just the one mentioned in the rationale:

| Proposal ID prefix | Description | State at pinned block | For / Against votes |
|---|---|---|---|
| `40206354…` | “Owner migration: transfer treasury ownership from old timelock to Safe updater” | Defeated; not canceled; not executed | 0 / approximately 4,975,799 veOLAS |
| `65184818…` | “Treasury and token controller upgrade to Safe v2.1 module” | Defeated; not canceled; not executed | 0 / approximately 4,961,280 veOLAS |

Exact integers, payloads, proposer addresses, deadlines, and states are in [Evidence references: proposals.json](../EVIDENCE.md#proposals) and [Evidence references: enrichment.json](../EVIDENCE.md#guard-configuration). Both voting deadlines precede proposal 15's execution. Therefore the evidence does **not** support attributing their defeat to the new threshold or quorum. Their titles are proposer-supplied descriptions, not verified descriptions of recipient safety.

The first proposer's voting power is approximately **115,083.54** at the pinned block's preceding block, versus approximately **115,815.17** just before proposal 15 executed. The DAO proposer has approximately **2,360,027.75** at the pinned block, with lock end **September 2, 2027**. Those readings invalidate using the original 5,100-OLAS narrative or the test comment's January 7, 2027 lock end as current inputs. Full holder enumeration was not performed; the “twelve to five addresses” eligibility claim remains unverified for the relevant historical block.

## 2. Findings and unresolved issues

### P1-01 — Activation artifact diverges from the executed payload

**Classification:** confirmed auditability/validation gap; no financial severity assigned without reviewing the additional targets.

The repository's proposal ID is `45361663242668069089223946785328365668773778141285203022311518232566090656298`; the executed ID is `12787157053706200851343001046637724671654439993200561198827574314576400014413`. Both hashes were recomputed independently from their respective arrays and descriptions.

- Calls **0–13 match exactly**, including the four grants, four revocations, bridge configuration, allowlist, and guard swap.
- Call **14**, the Celo message, differs and includes an additional packed action in the executed version.
- Call **15**, the Tokenomics upgrade, matches.
- Calls **16–21** are extra L1 or bridge calls absent from the committed artifact. The on-chain description adds ServiceManager upgrades across Ethereum and supported L2s.

**Implication:** a passing test against the committed 16-call builder cannot validate the full 22-call execution. This is not evidence of an incorrect role migration, because those calls match and their state transitions were verified.

**Why unresolved:** no explanation for the final on-chain expansion or for leaving the artifact unchanged was established in the collected PR bodies/reviews. Do not infer a reason from the mismatch alone.

**Required follow-up:** preserve the submitted 22-call version alongside the original draft, bind it to the actual proposal ID and execution transaction, and validate its additional targets and destination-chain effects in areas 2/4. Full differences are in [Evidence references: analysis.json](../EVIDENCE.md#governance-activation-and-parameters), `artifacts.11.comparisons`.

### P1-02 — Delay desynchronization blocks newly queued governance repairs

**Scope status:** retained background verification of an existing vulnerability-register entry; not a new finding or a separate open task in the current checklist.

**Classification:** known issue, active code exposure but dormant configuration; potentially significant governance liveness impact conditional on an approved unsafe parameter change. Registry §13 labels it Informative; that label should not be read as evidence of easy recovery.

`queue()` passes `governorDelay` unchanged to the Timelock. An approved self-call raising `minDelay` above it succeeds, but subsequent queueing—including a proposal to repair `governorDelay`—reverts. The Governor setter only checks the inequality when that setter runs; it does not prevent a separate Timelock change from breaking it.

**Evidence:** five local tests include this cycle; `test_LiveDelayDesyncPreventsGovernanceRepair` reproduces it on the deployed contracts at block 26,032,428. The live guard returns **false** for `getTargetSelectorChainId(Timelock, updateDelay(uint256), 1)`. It also returns false for `grantRole`, Governor `setProposalThreshold`, and `updateGovernorDelay` on their respective targets.

**Disagreement in existing sources:** internal20 says the issue is recoverable through governance by raising the Governor delay first. That is valid as prevention **before** desynchronization, not as an ordinary post-failure repair. The current registry §13 describes the circular dependency and a conditional CM recovery route; the required allowlist condition is not satisfied in the collected state.

**Stated reason not fixed:** the registry accepts coordinated parameter updates and cites non-upgradeable contracts and the invasiveness of enforcing coupling through Timelock changes. This explains a deployment constraint, but does not prove that no Governor-side change is possible. A future Governor could schedule with at least `max(governorDelay, minDelay)`; that option needs review of its timing semantics.

**Recovery follow-up:** [fork tests](ROLES_AND_RECOVERY.md) now demonstrate atomic coupled updates, a repair queued before the mismatch, and CM repair after conditional guard release. The exact heartbeat is unknown at the pin; tests mock its Defeated state explicitly. Establish those operational prerequisites before treating CM recovery as available. Do not add broad CM permissions without assessing the resulting authority expansion. No universal irrecoverability claim is made.

### P1-03 — Invalid Timelock replacement remains accepted

**Scope status:** retained background verification of an existing vulnerability-register entry; not a new finding or a separate open task in the current checklist.

**Classification:** existing issue, registry §25 Medium; governance-authorized lockout, not an external-access exploit.

`updateTimelock(address(0))` can pass through a valid governance execution; subsequent proposals cannot queue, including one intended to restore the old Timelock. Both local and live-fork tests reproduce this. The setter also lacks role/interface validation for other replacement addresses.

**Why unresolved:** the register defers validation/bounds to a future Governor deployment and relies on proposal review and role-wiring discipline. A specific reason for omitting the zero-address check from the deployed version was not established. The deployed Governor is non-upgradeable; a source fix alone would not change it.

**Recovery follow-up:** a pre-queued pointer-restoration proposal fails both through the broken Governor and directly through the old Timelock. [Conditional fork recovery](ROLES_AND_RECOVERY.md) replaces the Governor and migrates roles after guard release; it does not repair the broken instance. Operational release prerequisites and a complete production migration checklist remain open. Current configuration is valid: the Governor points to the existing Timelock and holds the required roles.

The other configuration hazards in registry §25 also remain relevant: an excessive proposal threshold can exclude every proposer, and extreme voting/execution delays can make governance impractical. The setters lack upper bounds; the voting period has a nonzero requirement and `governorDelay` has a floor relative to Timelock `minDelay`. These related cases were inspected in source but not separately reproduced on the live fork. The successful operation of today's parameter values does not establish that every value accepted by these setters is safe.

### P1-04 — Proposal 15 tests are time-dependent and one quorum assertion checks the old numerator

**Classification:** confirmed validation gap; previously raised in PR review, still present at the reviewed source snapshot.

- The existing suite forks latest state. On the collected run, **4 passed and 2 failed**: one expects threshold 5,000 even though execution raised it; the other expects the Treasury proposer's cancellation call to revert under the old threshold.
- Immediately after execution, line 202 checks `quorum(block.number - 1)`. The update checkpoint is at the execution block, so this reads **3%**, not the intended new **10%**. The new local quorum-history test demonstrates that boundary.
- The “legitimate proposal stays protected” test now uses proposal 13, which is already executed. A cancellation gate reverting first does not demonstrate protection of an active proposal.
- The test comment names a superseded lock expiry; source/README rationale uses historical voting-power figures in ways that can be mistaken for current facts.
- The generated proposal-15 HTML labels both setter selectors as unknown. The raw payload is correct, but the annotation does not explain the two actual actions.

**Why unresolved:** PR #233's review explicitly treated several of these remaining items as non-blocking follow-ups. That is a recorded review decision, not proof that they were subsequently fixed.

**Required follow-up:** pin a pre-execution fork for transition tests; add separate post-execution checks; advance a block before asserting new-quorum feasibility; create an actually active proposal for cancellation tests; regenerate annotations with the two setter selectors; date and source the voting-power rationale. No production code was changed during this review.

## 3. Consistency with design

| Design question | Assessment and limits |
|---|---|
| Can a non-upgradeable Governor be replaced by governance? | Yes. This is described in the original design and the role migration is verified. |
| Can governance adjust participation parameters? | Yes. The mechanism is explicitly part of the original design. It does not specify that 250,000 and 10% are optimal or require these exact values. |
| Can CM bypass the normal voting process for selected actions? | Yes, intentionally. Zero Timelock delay is an explicit later design decision in PR #178. The permitted scope still needs the separate GuardCM review. |
| Can CM directly change Governor-sensitive parameters? | Not through the tested direct Timelock path; `onlyGovernance` has an additional authorized-call check, and relevant settings are not in the current guard allowlist. This is not an exhaustive review of every Safe module or guard-release path. |
| Does the delay split preserve liveness under every allowed configuration? | No. Independent setters admit a state that prevents normal queueing; this is a confirmed design constraint requiring mitigation. |
| Does higher threshold/quorum guarantee protection from an adversarial proposal? | No. It restricts participation and raises the required voting power. Sufficient voting power still allows proposals and passage. Current large holders can individually exceed quorum. |

The original documents establish mechanisms and governance powers, not an objective function for choosing a socially optimal participation threshold. Reduced proposal access and increased resistance to low-power submissions are simultaneous effects; the evidence does not logically force a single judgment about that trade-off.

## 4. Validation, reproduction, and limits

Successful checks:

- 130 explorer events matched against RPC receipts, including activation and parameter-change execution evidence.
- Exact proposal-15 artifact match; exact detection and localization of proposal-11 divergence.
- Five local behavior tests passed; two block-pinned tests on deployed contracts passed using dRPC.
- Verified Governor source/dependency match and executable-bytecode comparison, with the exclusions described above.

Recorded failures and their interpretation:

- PublicNode rejected historical log/account-state requests. Blockscout pagination supplied event discovery; RPC receipts supplied cross-checks; dRPC supplied the successful pinned fork. Failed attempts remain recorded.
- The initial checkout lacked the pinned `forge-std` submodule; it was initialized before testing. Existing compiler cache was incompatible, so isolated `/tmp` build/cache paths were used.
- Existing proposal-15 latest-fork suite: two expected pre-state assumptions fail after deployment. Full output: [Evidence references: current-fork test log](../EVIDENCE.md#test-results). That run used block 26,032,488, slightly later than the primary evidence pin; it is not used as a state snapshot for the report.

Reproduce from the repository root:

```sh
python3 audits/2026-09-22-governance-review/point-1/collect_prs.py
node audits/2026-09-22-governance-review/point-1/collect_chain.cjs
node audits/2026-09-22-governance-review/point-1/enrich_chain.cjs
FOUNDRY_TEST=audits/2026-09-22-governance-review/point-1/tests forge test --match-contract '^GovernanceReviewTest$' --offline --cache-path /tmp/ai-review-governance-unit-cache --out /tmp/ai-review-governance-unit-out -vv
FOUNDRY_TEST=audits/2026-09-22-governance-review/point-1/tests forge test --match-contract '^GovernanceLiveReviewTest$' --offline --cache-path /tmp/ai-review-governance-unit-cache --out /tmp/ai-review-governance-unit-out -vv
node audits/2026-09-22-governance-review/point-1/analyze_evidence.cjs
```

Collectors reuse saved, pinned responses; rerunning does not silently move the evidence block. Fork tests perform only local mutations. Logs: [Evidence references: local mechanisms](../EVIDENCE.md#test-results), [Evidence references: deployed mechanisms](../EVIDENCE.md#test-results).

Remaining limits: operational heartbeat/recovery prerequisites, broader Safe authority analysis, complete veOLAS holder enumeration, destination-chain verification of the extra activation calls, and exhaustive exploration of exceptional recovery paths. Deployment-to-pin role reconstruction and bounded module/guard-release checks are now covered by the [follow-up](ROLES_AND_RECOVERY.md). Event discovery depends on explorer completeness; verifying returned events against receipts does not prove no events were omitted. PR metadata was collected, not every inline discussion. The historical design PDFs were inspected as extracted text, not as rendered diagrams.

**Review summary:** the principal activation and parameter changes are live and their core state transitions match the intended governance mechanisms. The known configuration risks and recovery caveats above remain background evidence for the existing vulnerability register; they are not separate open work in the current checklist. The strongest newly established process gap is that the committed activation artifact does not represent the entire executed proposal.
