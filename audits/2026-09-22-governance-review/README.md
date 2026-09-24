# Governance AI review — scope, evidence, and method

**Ongoing review, September 22, 2026.** Start with [SUMMARY.md](SUMMARY.md) for completed and open work. Production contracts are unchanged.

This review asks what changed and why, whether changes were activated, whether they introduce regressions or depart from the design, and which existing issues remain unresolved and with what impact.

## Governance-only scope and current position

The three workstreams are **(1) proposals, deployments, roles and timing; (2) GuardCM and cross-chain permissions; (3) contract changes and regressions**, including VoteWeighting and veto. External targets are examined where needed to establish governance authority and effects, without a standalone audit of their business logic.

Main governance activation, roles and current parameters have been verified at the recorded block. Holder voting capacity — proposal eligibility, quorum coverage and lock-expiry scenarios — is deferred to a separate voting-power follow-up and is not published here. The historical VoteWeighting is confirmed active; the revised version is not wired into the canonical system at the review block or fresh block 26,034,116. No separate revised deployment was found in the bounded discovery. The focused CM change/configuration review, veto adoption and remaining source-fix/regression reviews are open. The vulnerability register is the baseline for existing issues; the active checklist focuses further analysis on reviewed changes, claimed fixes and new evidence. Proposal-15 test weaknesses are a documented finding, not an obstacle to the independently verified execution.

### CM review boundary

Review **source changes, activation, changed permissions/routes and applicable unresolved findings**. Reuse prior tests/audits for unchanged behaviour only after identifying the covered source version, relevant test cases, findings and assumptions, and checking that those assumptions still apply to the activated configuration. Record reliance on prior coverage separately from independent verification. Prior code tests do not prove a later deployment or configuration correct.

The source baseline and proposal window are unchanged: the March zero-mediator check remains in scope because it follows the selected baseline. Keep targeted checks for Celo, new/changed routes, and the July L1 Dispenser permission. Check unchanged dependencies only as needed to establish those behaviours. New tests are justified by relevant changes, missing coverage or contradictory evidence.

One bounded operational question remains in scope: do the responsible maintainers retain a secure, retrievable copy of the exact heartbeat proposal inputs, and have they privately verified that those inputs reproduce the active GuardCM ID? The source intentionally withholds these parameters; their custody and correctness are unverified. Record confirmation and an evidence reference without publishing the inputs. This does not require a full recovery runbook. [Source explanation](../../contracts/multisigs/GuardCM.sol); [conditional recovery limitations](point-1/ROLES_AND_RECOVERY.md).

**Deferred, not completed:** a full Safe/module audit, exhaustive permission-combination tests, revalidation of every unchanged L2 integration, a general cross-chain token inventory, and a full operational recovery/migration runbook. Reopen a specific part if a reviewed change or evidence gap makes it necessary. Completed role and recovery results remain supporting evidence; deferral neither fixes known issues nor establishes recoverability.

This boundary applies to CM/bridge work. VoteWeighting and veto review scopes remain unchanged. The final design still describes all governance contracts, with explicit evidence/coverage labels; describing an unchanged component does not require a fresh security audit of it. The focused checklist is in [section 2](SUMMARY.md#2-guardcm-and-cross-chain-permissions).

## 1. Which versions are compared?

Source scope starts at the last tag before May 1, 2026: `v1.2.5-post-external-audit` → `v1.2.5` → `v1.3.0-pre-external-audit`. The last tag matches collected main at `93901ec315eb2b1d4683aab5615ef38b071228f8`. All adjacent tag differences are included; commit dates are not filtered. Exact hashes and dates: [source references](EVIDENCE.md#source-versions).

The separate proposal window is May 1, 2026, 00:00 Europe/Rome through September 22. Earlier state is context where necessary. Main Ethereum state is pinned to block **26,032,428**; the proposal inventory ends at **26,032,401**. [Pins and addresses](EVIDENCE.md#pins-and-addresses).

## 2. How are the source differences obtained?

The collectors resolve tags with `git rev-parse`, compare contents with `git diff`, and inventory integrations with `git log`. This establishes source changes, not deployment or security conclusions. The [inventory script](collect_inventory.py) and [tag collector](collect_tag_lineage.py) pin the source snapshot.

```sh
python3 audits/2026-09-22-governance-review/collect_inventory.py
python3 audits/2026-09-22-governance-review/collect_tag_lineage.py
python3 audits/2026-09-22-governance-review/render_tag_lineage.py audits/2026-09-22-governance-review/tag-lineage.html
```

The renderer uses the retained [HTML template](tag-lineage.template.html); the generated visualization and diffs stay local.

## 3. What is committed?

| Files | Purpose |
|---|---|
| [SUMMARY.md](SUMMARY.md) | Current checklist and detailed review questions. |
| [Area 0](onchain/AREA0.md) | Proposal inventory, effects and limitations. |
| [Point 1](point-1/README.md) | Governance activation, parameters, design assessment and findings. |
| [VoteWeighting deployment](point-3/DEPLOYMENT.md) | Active version, canonical wiring and bounded replacement discovery, with compact references and a read-only collector. |
| [Roles and recovery](point-1/ROLES_AND_RECOVERY.md) | Role-history evidence and retained background checks of already documented findings; these are not separate open review tasks. |
| [EVIDENCE.md](EVIDENCE.md), [evidence.json](evidence.json) | Compact source references, transaction IDs, pins, recorded results and input hashes. |
| Collection/analysis scripts and `point-1/tests/` | How to reproduce the analysis and mechanisms. |

Raw RPC/explorer responses, intermediate JSON/CSV/diffs, copied PR/design text and verbose test logs are **not committed**. They are preserved locally in ignored data directories. Earlier overlapping plans/notes and a full pre-cleanup backup are also local-only. Reports link to the compact index or primary sources instead of absent files.

The compact index records findings derived from the original collection; it is not independent chain proof. Hashes identify summarized input files but cannot reconstruct them. Independent reproduction requires recollecting historical data. See [evidence limitations](EVIDENCE.md#reproduction-and-limits).

## 4. Reproduction

Run from the repository root with the repository Node dependencies and Solidity/Foundry dependencies installed. Python scripts use the standard library except optional design extraction (`pypdf`); PR collection uses authenticated `gh`. Historical chain collectors/forks need network access to an archive-capable Ethereum provider and explorer. Public service availability is not guaranteed. The committed point-1 pin prevents silently moving its snapshot to latest.

For proposal and guard evidence, run in order:

```sh
node audits/2026-09-22-governance-review/onchain/collect_logs.js
node audits/2026-09-22-governance-review/onchain/decode_logs.js
python3 audits/2026-09-22-governance-review/onchain/check_point0.py
node audits/2026-09-22-governance-review/onchain/reconstruct_guard.cjs
```

For main governance evidence, run in order:

```sh
node audits/2026-09-22-governance-review/point-1/collect_chain.cjs
node audits/2026-09-22-governance-review/point-1/enrich_chain.cjs
node audits/2026-09-22-governance-review/point-1/collect_role_history.cjs
FOUNDRY_TEST=audits/2026-09-22-governance-review/point-1/tests forge test --match-contract '^GovernanceReviewTest$' --offline --cache-path /tmp/ai-review-governance-unit-cache --out /tmp/ai-review-governance-unit-out -vv
node audits/2026-09-22-governance-review/point-1/analyze_evidence.cjs
node audits/2026-09-22-governance-review/point-1/verify_saved_roles.cjs
```

The local test command also builds the Governor artifact used by the bytecode comparison. To reproduce fork scenarios, use the same command with `--match-contract '^Governance(Live|Recovery)ReviewTest$'` and, optionally, `REVIEW_RPC`. `--offline` prevents compiler downloads, not RPC requests. Tests mutate only a local fork; collectors do not sign or broadcast transactions.

Optional documentary inputs: `point-1/collect_prs.py` and `point-1/collect_design.py`. The existing proposal-15 suite is `test/proposals/Proposal15GovernorParams.t.sol`; its recorded latest-fork failures are historical and depend on the fork state.

The compact reference checker works from a fresh clone without raw evidence:

```sh
python3 audits/2026-09-22-governance-review/check_summary_evidence.py
```

To rebuild `evidence.json`, first regenerate both source and chain evidence and save the four named test outputs listed in its `inputSha256` map, then run `build_evidence_index.py`. Recollection may produce different formatting/hashes or service responses; review differences before replacing the recorded index. This packaging step does not rerun the analysis itself.

## 5. What can a net diff miss?

The baseline tag is on an audit branch. Changes it already contains may appear as later integrations into main without being new in the endpoint diff. Governor logic and some verifier fixes predate the baseline, while their activation remains in scope. Net production logic changes occur in GuardCM and VoteWeighting. Source, deployment and activation must be assessed separately; tag names do not prove audit completion.

## 6. What has been verified beyond Git?

[Area 0](onchain/AREA0.md) records the proposal inventory. [Point 1](point-1/README.md) records activation, parameters, source/runtime checks and reproductions. [The follow-up](point-1/ROLES_AND_RECOVERY.md) extends role history through deployment and tests conditional recovery. [VoteWeighting deployment verification](point-3/DEPLOYMENT.md) identifies the historical active version at the original pin and block 26,034,116. Each report retains its own block and coverage limits; destination-chain operation is not established by L1 execution alone.

## 7. Remaining limits and how to record conclusions

For each change/finding, record source interval, motivation (or unknown rationale), live status, design assumptions, reproduction, impact, recovery conditions and documented reasons for non-fix. Preserve conflicting assessments until evidence resolves them. Public RPC/explorer completeness is an assumption; successful receipt matching authenticates returned logs, not the absence of omitted events. Unmerged proposals/fixes and discussions not collected remain outside the evidence set.

## 8. Final deliverable: implemented governance design

Produce a concise catalogue and interaction diagram covering **all governance contracts**, including unchanged components: OLAS/veOLAS/wveOLAS, Governor/Timelock, CM Safe/guard/verifiers, cross-chain mediators, VoteWeighting and veto where applicable. Describe roles, caller/target relationships, data/value flows, voting/queue/execute/cancel paths, migration/recovery and timing. Separate governance contracts from externally governed targets.

Identify each active instance by chain/address/version and link substantive claims to source and pinned evidence. Distinguish active deployment, source-only changes, planned mechanisms, retired routes and unknown states. Complete this synthesis after the three workstreams and known-issue/test review are reconciled within the stated scope; label reliance on prior coverage and deferred independent verification; unknowns must remain explicit.
