# Point 1 follow-up — complete role history and lockout recovery

**Scope status:** role-history results remain evidence for the active review. The two configuration cases below correspond to vulnerability-register §§13 and 25 and are retained as background verification of existing findings. Their suggested recovery follow-ups are not separate open tasks or completion requirements in the current review checklist. This scope decision does not establish that the issues are fixed or that recovery is available.


**Evidence packaging:** this report describes the original pinned collection. Published links now lead to the [compact evidence index](../EVIDENCE.md) or original sources. Raw RPC responses, generated JSON and verbose test logs remain local/ignored; [reproduction instructions](../README.md#4-reproduction) explain how to recollect them.


**Snapshot:** Ethereum block **26,032,428**, September 22, 2026, 10:27:59 UTC; hash `0x4676a14bf8236315a34cfd31f5c308ae66553b574a3ee701db2458f26e6e4fd6`. This extends the earlier point-1 report using its existing pin. No transaction was broadcast and no production contract was changed.

**Result:** the deployment-to-pin role reconstruction matches the expected holders. Both unsafe configuration changes remain possible through approved governance. Neither failure is active at the pin. Recovery depends on the particular failure, previously queued operations, and availability of guard release; it is not an unconditional CM power.

## 1. Who actually controls the Timelock?

| Role | Reconstructed holders at the pin | Role that administers it |
|---|---|---|
| `TIMELOCK_ADMIN_ROLE` | Timelock and current Governor | `TIMELOCK_ADMIN_ROLE` |
| `PROPOSER_ROLE` | Current Governor and CM Safe | `TIMELOCK_ADMIN_ROLE` |
| `EXECUTOR_ROLE` | Current Governor and CM Safe | `TIMELOCK_ADMIN_ROLE` |
| `CANCELLER_ROLE` | Current Governor only | `TIMELOCK_ADMIN_ROLE` |
| `DEFAULT_ADMIN_ROLE` | None | `DEFAULT_ADMIN_ROLE` |

Addresses: Timelock `0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE`; Governor `0x060D0CBdDFb0498d610E2EF55C01516B5B1251E6`; CM `0x04C06323Fe3D53Deb7364c0055E1F68458Cc2570`. Neither retired Governor nor the deployment account retains these roles. The zero address has no executor role, so execution is not opened to everyone by that mechanism.

**How obtained:** [collect_role_history.cjs](collect_role_history.cjs) requests `RoleGranted`, `RoleRevoked`, and `RoleAdminChanged` from genesis through the pin, sorts the returned logs, and replays grants, revocations, and admin changes. It found **31 events**. Every returned event is matched against its successful transaction receipt. The reconstructed memberships are compared with pinned `hasRole` calls for every historical/named candidate, and each role's administration with `getRoleAdmin`.

The first role events occur at block **15,049,940**. Code is absent at the preceding block and present at that block, establishing that the collected interval includes deployment. The deployed Timelock's explorer-published `AccessControl` source updates membership in `_grantRole` / `_revokeRole` and emits the corresponding events; `_setRoleAdmin` emits administration changes. Its constructor sets the operational roles' admin to `TIMELOCK_ADMIN_ROLE`. The deployed version, rather than the checkout's newer Timelock constructor, is the relevant source: [Evidence references: verified source bundle](../EVIDENCE.md#source-verification).

| Historical event | Block |
|---|---:|
| Deployment grants Timelock/deployer admin and CM operational roles, including canceller | 15,049,940 |
| First Governor receives its roles | 15,050,311–15,050,319 |
| Deployment account's admin revoked | 15,051,102 |
| First Governor replaced by second Governor | 17,598,156 |
| CM canceller revoked | 18,266,403 |
| Second Governor replaced by current Governor | 25,322,326 |

Exact addresses, role hashes, event order and transaction hashes: [Evidence references: events](../EVIDENCE.md#roles-and-recovery). Current reads and reconciliation: [Evidence references: result](../EVIDENCE.md#roles-and-recovery). Original [Evidence references: logs](../EVIDENCE.md#roles-and-recovery), [Evidence references: receipts](../EVIDENCE.md#roles-and-recovery), and `data/role-history/rpc/` preserve the inputs.

**Meaning of admin:** it authorizes role grants/revocations. It does not let an arbitrary caller invoke `Timelock.updateDelay`: that function requires a call from the Timelock itself. A scheduled operation targeting the Timelock is how a proposer/executor can make that self-call. The current Governor has no generic externally callable function for exercising its admin identity outside its governance mechanisms.

**Completeness limit:** this is deployment-to-pin enumeration under the deployed AccessControl event semantics and the RPC provider's log completeness. Receipt checks authenticate returned events; they cannot prove the provider omitted none. No additional holder emerged under this reconstruction.

## 2. Delay desynchronization: what breaks, and how can it recover?

At the pin, `governorDelay = 157092` seconds and Timelock `minDelay = 0`. These are compatible. The Governor always passes its own delay to `scheduleBatch`; the Timelock requires that value to be at least its minimum.

The fork reproduction uses **200,000 seconds as a hypothetical new minimum**, not an observed setting:

1. A governance proposal is approved, queued under the old minimum, and executed to set Timelock `minDelay = 200000`.
2. Governor delay remains `157092`. New `queue()` calls now revert because `157092 < 200000`.
3. Voting can still succeed, but a new proposal to raise the Governor delay cannot pass the broken queue step.

This is a governance-authorized loss of liveness. An outsider cannot directly call either unsafe setter. It can prevent voted Treasury/permission/upgrade actions from proceeding, without itself transferring assets. Existing allowed CM operations remain a separate path, but must now respect the raised Timelock minimum.

**Prevention tested:** execute both delay changes in one proposal batch. The test raises Timelock minimum and then Governor delay in the same transaction, verifies equality, and successfully processes a later proposal. All-or-nothing execution avoids leaving the intermediate mismatch committed.

**Pre-queued repair tested:** a Governor proposal to raise its delay, queued before the mismatch, still executes afterward. Changing the Timelock minimum does not retroactively change its scheduled timestamp. The test then successfully processes a new proposal. This requires a suitable operation to have been queued in advance; it does not rescue every accidental change.

**CM while guarded:** scheduling `Timelock.updateDelay` is rejected by the deployed GuardCM. Scheduling a role grant is also rejected. Holding proposer/executor roles alone is insufficient to use these repairs through the guarded Safe.

**CM after conditional release:** the fork demonstrates CM scheduling and executing a Timelock self-call to lower its minimum, after waiting the raised minimum, followed by successful Governor operation. Guard release is a separate prerequisite described below. This is not instantaneous recovery if the minimum has already become excessive.

## 3. Zero Timelock pointer: why it is a different failure

An approved proposal can execute `Governor.updateTimelock(address(0))`. The setter does not reject it. This changes the Governor's Timelock/executor pointer; it does not destroy the old Timelock or remove its ownership of governed targets.

New queueing fails. A proposal restoring the old pointer, even if queued beforehand, cannot execute through the broken Governor. Executing that queued call directly from the old Timelock also fails: `onlyGovernance` now expects the Governor's executor to be the zero address. These are separate tested failures.

**Conditional replacement tested:** after the zero-pointer failure and conditional guard release, CM schedules a batch on the still-functional original Timelock that grants all four roles to a newly deployed Governor, revokes them from the broken Governor, and updates GuardCM's Governor reference. A proposal through the replacement Governor then re-enables guard restrictions. The replacement uses the current Governor source and the pinned token/parameters.

This restores a governance route through a **replacement instance**; it does not repair the old instance or automatically migrate its proposals. Full production migration checks—other Governor references, in-flight operations, user interfaces, heartbeat configuration—remain necessary. An EOA cannot simply impersonate the old Timelock to repair the pointer.

## 4. Is guard release available now?

Pinned GuardCM: `0xC0b146D61e2A2C17E024477E01978D1Fcf598c6B`; `paused = 1`, meaning restrictions are enforced. Calling `pause()` sets it to `2`, releasing restrictions; the name refers to pausing the **guard**.

- The owner Timelock can release the guard by calling `pause()`.
- CM can release it only if `state(governorCheckProposalId)` on the configured Governor is **Defeated**.
- At the pin, that exact proposal ID returns **“Governor: unknown proposal id”**. Calling release through the actual Safe fails (`GS013` wraps the target failure).
- Enumerating CM Safe modules through the sentinel returns **only the Timelock**. There is no additional enabled module in this snapshot that supplies an independent recovery authority. This does not constitute an exhaustive Safe security review.

The fixed heartbeat ID is `88250008686885504216650933897987879122244685460173810624866685274624741477673`. An arbitrary defeated proposal does not satisfy the check. The matching proposal inputs/description, ability to propose it, voting outcome, and CM threshold cooperation must be established. Merely waiting a week does not release the guard automatically.

For the conditional recovery tests, **only the heartbeat's `state()` response is mocked to Defeated**. Safe approval checks, GuardCM release, Timelock operations, and subsequent Governor actions execute in the local fork. Owners are locally impersonated to approve the Safe transaction hash; this assumes threshold cooperation and is not evidence of access to signing keys. The tests do not prove the heartbeat's preimage is known or that it can be made Defeated operationally. Both reproduced failures leave proposing/voting available in principle, but the exact heartbeat prerequisites remain unverified.

| Route | Delay mismatch | Zero pointer |
|---|---|---|
| Newly voted repair through affected Governor | Queue fails | Queue fails |
| Repair already queued through affected Governor | Tested successful for Governor delay | Tested failed for pointer restoration |
| CM schedules sensitive repair with current guard enforced | Tested rejected | Role grant tested rejected |
| CM after a defeated heartbeat releases guard | Tested: lower Timelock minimum, after its delay | Tested: replace Governor and migrate roles |
| Suitable pre-queued Timelock/guard emergency operation | Depends on its exact payload/readiness | Depends on its exact payload/readiness |

The existence of a suitable emergency operation at the pin has **not** been established through a complete deployment-to-pin operation inventory. The last row must not be read as evidence that such a transaction is ready. No universal irrecoverability claim is made.

## 5. Why are the issues unresolved, and do the documents agree?

- [Vulnerability register §13](../../../docs/Vulnerabilities_list_governance.md#13-governordelay-and-timelock-mindelay-desynchronization) records the circular repair dependency, accepts coordinated parameter changes, and cites non-upgradeability/the invasiveness of coupling Timelock changes. Its CM route explicitly requires an allowlist permission that is absent at the pin. Its admin discussion also needs precision: `updateDelay` is self-call-only, not merely admin-only.
- [Internal20 F-7](../../../audits/internal20/README.md) says “raise governorDelay first” is recovery. That is valid prevention before the mismatch; a newly queued repair afterward fails. A future Governor could use `max(governorDelay, minDelay)` when scheduling, subject to a review of timing semantics; modifying source would not update the deployed instance.
- The same register's **§25** says §13 can be corrected by a subsequent proposal. That conflicts with §13's own mechanism and the fork reproduction unless an additional route, such as a pre-queued repair, is assumed. The Informative/Medium distinction based on that unqualified recoverability claim is therefore not established.
- **§25** recommends bounds, a zero-address rejection and replacement-role validation on redeployment. It relies on proposal review and migration discipline in the meantime. The collected evidence does not establish a specific reason why the zero-address check was omitted from the current deployed Governor. Non-upgradeability explains why a source-only patch cannot fix it in place; it does not explain every earlier design choice.

Both cases require governance authorization. That limits reachability; it does not prove deliberate governance disruption has no motive or that operator error is the only possible trigger. Significant governance unavailability remains possible even without immediate asset extraction. This follow-up records conditions and evidence without assigning a new unconditional severity.

## 6. Reproduction and remaining work

```sh
node audits/2026-09-22-governance-review/point-1/collect_role_history.cjs
FOUNDRY_TEST=audits/2026-09-22-governance-review/point-1/tests forge test --match-contract '^GovernanceRecoveryReviewTest$' --offline --cache-path /tmp/ai-review-governance-unit-cache --out /tmp/ai-review-governance-unit-out -vv
```

The collector reuses saved pinned responses. Fork tests require an archive-capable RPC (the parent test accepts `REVIEW_RPC`, default dRPC); `--offline` prevents compiler downloads, not RPC reads. [Test source](tests/GovernanceRecoveryReview.t.sol); [Evidence references: output](../EVIDENCE.md#test-results): **9 passed**, including the two inherited original reproductions. Initial harness failures concerned assertion ordering and Safe's wrapped revert reason; both were corrected before the successful run.

- [x] Reconstruct deployment-to-pin role membership and administration, with provider completeness limits.
- [x] Reproduce both failures on deployed contracts and verify direct outsider rejection.
- [x] Test atomic delay prevention, pre-queued repair behavior, guarded CM rejection, and conditional released-CM recovery.
- [x] Read heartbeat state and enumerate enabled CM modules at the pin.
- [x] Compare documented mitigations/non-fix reasons with the reproduced behavior and preserve contradictions.
- [ ] Establish an operational heartbeat/recovery procedure: matching proposal availability, eligibility, possible defeat, signer cooperation, timing and return to restricted operation.
- [ ] Inventory suitable outstanding emergency operations across the full Timelock history if relying on a pre-queued recovery route.
- [ ] Complete the broader Safe/guard authority review and production Governor replacement checklist.
- [ ] Review other unbounded setters and remaining point-1 findings separately; these nine tests do not close the entire governance audit.
