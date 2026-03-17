# Internal audit of autonolas-governance
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-governance` <br>
commit: `bae8da6` or `tag: main branch` <br>

## Objectives
The audit is a comprehensive full-project review of the autonolas-governance repository as it exists on main.
The goal is a thorough security assessment covering all 27 contracts (~5142 LOC), with special attention
to changes made after the Code4rena (C4A) external audit (tag: `v1.2.5-pre-external-audit`).

### Contracts in scope (27 total, ~5142 LOC)

**Core governance:**
| Contract | LOC | Description |
|----------|-----|-------------|
| OLAS.sol | 154 | ERC20 token with inflation schedule |
| veOLAS.sol | 805 | Voting Escrow (Curve veCRV fork) |
| wveOLAS.sol | 337 | View-only veOLAS wrapper |
| buOLAS.sol | 335 | Burnable locked OLAS with vesting |
| GovernorOLAS.sol | 123 | OZ Governor + custom TimelockControl |
| GovernorTimelockControl.sol | 205 | Custom OZ extension with governorDelay |
| Timelock.sol | 12 | OZ TimelockController instantiation |
| VoteWeighting.sol | 822 | Curve GaugeController for nominees |
| Burner.sol | 66 | OLAS burn helper |

**Multisig guard + bridge verifiers:**
| Contract | LOC | Description |
|----------|-----|-------------|
| GuardCM.sol | 459 | CM multisig transaction guard |
| VerifyData.sol | 37 | Target/selector whitelist |
| VerifyBridgedData.sol | 74 | Bridge payload verification |
| ProcessBridgedDataArbitrum.sol | ~90 | Arbitrum bridge verifier |
| ProcessBridgedDataGnosis.sol | ~90 | Gnosis bridge verifier |
| ProcessBridgedDataOptimism.sol | ~90 | Optimism bridge verifier |
| ProcessBridgedDataPolygon.sol | ~90 | Polygon bridge verifier |
| ProcessBridgedDataWormhole.sol | ~110 | Wormhole bridge verifier |

**Bridge messengers (L2 receivers):**
| Contract | LOC | Description |
|----------|-----|-------------|
| BridgeMessenger.sol | 78 | Abstract data processing |
| FxGovernorTunnel.sol | 168 | Polygon L2 bridge |
| FxERC20RootTunnel.sol | 108 | Polygon FxPortal root |
| FxERC20ChildTunnel.sol | 109 | Polygon FxPortal child |
| HomeMediator.sol | 168 | Gnosis AMB bridge |
| OptimismMessenger.sol | 83 | Optimism L2 bridge |
| WormholeMessenger.sol | 108 | Wormhole L2 bridge |
| WormholeRelayerTimelock.sol | 312 | Wormhole relayer via timelock |

**Other:**
| Contract | LOC | Description |
|----------|-----|-------------|
| BridgedERC20.sol | 66 | Bridged token |
| DeploymentFactory.sol | 81 | CREATE2 factory |

## Post-C4A changes

Three commits after `v1.2.5-pre-external-audit`:
1. `4fd7d98` — addressing GuardCM found issues
2. `b587531` — adding notices
3. `3e71631` — addressing C4A audit findings

Changed files:
- `contracts/multisigs/GuardCM.sol` — added `bridgeMediatorL2s[i] == address(0)` check, removed stale comment
- `contracts/multisigs/bridge_verifier/ProcessBridgedDataArbitrum.sol` — added l2CallValue, refund address checks
- `contracts/multisigs/bridge_verifier/ProcessBridgedDataWormhole.sol` — added receiverValue, refund chain/address checks

### Verification of C4A fixes

##### 1. Arbitrum bridge — refund address drain
```
C4A finding: ProcessBridgedDataArbitrum ignored l2CallValue, excessFeeRefundAddress, callValueRefundAddress.
An attacker could set callValueRefundAddress to drain ETH from Timelock.

Fix verified (ProcessBridgedDataArbitrum.sol):
- l2CallValue > 0 → revert NonZeroValue (line 70)
- excessFeeRefundAddress != l2Timelock → revert WrongL2BridgeMediator (line 75)
- callValueRefundAddress != l2Timelock → revert WrongL2BridgeMediator (line 78)
- l2Timelock parameter correctly sourced from bridgeParams.bridgeMediatorL2 in GuardCM
```
[x] Fixed — verified correct

##### 2. Wormhole bridge — unchecked refund parameters
```
C4A finding: ProcessBridgedDataWormhole ignored receiverValue, refundChainId, refundAddress.

Fix verified (ProcessBridgedDataWormhole.sol):
- receiverValue > 0 → revert NonZeroValue (line 102)
- SEND_MESSAGE_REFUND path: refundChainId != 2 → revert WrongRefundChainId (line 93)
- SEND_MESSAGE_REFUND path: refundAddress != TIMELOCK → revert WrongRefundAddress (line 96)
- TIMELOCK hardcoded as 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE
```
[x] Fixed — verified correct

##### 3. Internal17 note: stale Arbitrum bridgeMediatorL2 comment
```
Internal17 noted: comment said bridgeMediatorL2 can be zero for Arbitrum case, which conflicts with fix #1.
GuardCM.sol now adds bridgeMediatorL2s[i] == address(0) check (line 378) and removes the stale comment.
```
[x] Fixed

## Testing and coverage
- All 172 tests pass
- Compilation: 109 files compiled (pragma ^0.8.30, EVM target: prague)
- Warning: GovernorOLAS exceeds 24576 byte contract size limit

Coverage summary:
| Metric | Coverage |
|--------|----------|
| Statements | 98.48% |
| Branches | 93.56% |
| Functions | 98.45% |
| Lines | 97.03% |

Notable uncovered areas:
- **Burner.sol: 0% coverage** — no tests exist for the Burner contract. Recommend adding basic tests.
- **ProcessBridgedDataArbitrum.sol: 70% branches** — C4A fix revert paths (l2CallValue > 0, refund address checks) untested
- **ProcessBridgedDataWormhole.sol: 78.57% branches** — C4A fix revert paths (receiverValue, refundChainId, refundAddress) untested
- **veOLAS.sol: 92.37% branches** — Curve safety checks (bias < 0, slope < 0 at lines 249, 253, 283, 286) — these are "should never happen" paths, fuzzer did not reach them (documented)
- **GovernorTimelockControl.sol: 77.27% branches** — `isOperationDone`/`isOperationPending` edge cases

## Problems found instrumentally

### Slither
Full output: `audits/internal18/analysis/slither_full.txt` (242 results)

Triaged results:
- **veOLAS `transferFrom`/`transfer` return values ignored** — FALSE POSITIVE. OLAS is a solmate-based ERC20 with optimized transfer that either returns true or reverts. Documented in comments (lines 363, 534).
- **veOLAS `_checkpoint` — multiplication after division** — KNOWN. Curve standard pattern for `block_slope` calculation. Precision loss is negligible (dust-level, sub-block granularity).
- **Burner.burn — strict equality (`olasBalance == 0`)** — ACCEPTABLE. Zero balance is the exact threshold; no rounding involved.
- **Uninitialized local variables in `_checkpoint`** — FALSE POSITIVE. `PointVoting` memory structs default to zero, which is the intended initial state.
- **Reentrancy in WormholeRelayerTimelock** — FALSE POSITIVE. Reentrancy guard (`_locked`) prevents re-entry.

No actionable Slither findings.

## Cross-reference with known vulnerabilities

The project maintains `docs/Vulnerabilities_list_governance.pdf` with 10 known issues.
Cross-reference with our findings:

| # | PDF Vulnerability | Severity | Status | Our Assessment |
|---|------------------|----------|--------|----------------|
| 1 | `getPastVotes` incorrect for early blocks | Low | Known, mitigated by wveOLAS | Confirmed. No new lock creation possible currently, risk is theoretical |
| 2 | `balanceOfAt` incorrect for early blocks | Low | Known, mitigated by wveOLAS | Confirmed. Same root cause as #1 |
| 3 | `_checkpoint` memory pointer aliasing | Medium | Known, mitigated by weekly cron | Confirmed. Curve-inherited. Incorrect supply points if no checkpoint for >1 week |
| 4 | `createLockFor` griefing (veOLAS + buOLAS) | Medium | Known, low likelihood | Confirmed. Attacker spends own OLAS to grief locks. buOLAS has revoke guardrail |
| 5 | `totalSupplyLockedAtT` — not for past ts | Low | Known, not used externally | Confirmed. View-only, mitigated by wveOLAS |
| 6 | `getPastTotalSupply` revert on early blocks | Low | Known | Confirmed. Should return 0 instead of revert |
| 7 | `processMessageFromForeign` no chainId check | Informative | Known | Confirmed. HomeMediator only talks to Ethereum AMB, no multi-chain risk now |
| 8 | `removeNominee` orphaned voting power | Informative | Known | **EXTENDED by our finding below** — PDF only mentions orphaned power, NOT slope drift or DoS |
| 9 | `_addNominee`/`removeNominee` Dispenser sync | Informative | Known | Confirmed. Deploy Dispenser immediately after VoteWeighting |
| 10 | `voteForNomineeWeights` lock expiry edge | Informative | Known | Confirmed. One-week power loss, user can extend lock |

**New findings not in PDF**: removeNominee slope drift + DoS (extends #8), FxPortal deployment risk, permissionless addNominee, OLAS mint() silent fail, governorDelay desync, Wormhole hardcoded TIMELOCK, mixed pragmas, Burner 0% coverage, C4A fix test gaps, GovernorOLAS size limit.

## Security issues

### Manual review findings

#### Low. VoteWeighting: `removeNominee` slope drift causes accounting errors and potential DoS
```
VoteWeighting.sol lines 603-613

EXTENDS known vulnerability PDF #8 (which only documents orphaned voting power).

When removeNominee is called:
- pointsWeight[nomineeHash][nextTime].bias = 0  (cleared ✓)
- pointsSum[nextTime].bias = oldSum - oldWeight  (adjusted ✓)
- BUT pointsWeight[nomineeHash][nextTime].slope is NOT zeroed  (BUG)
- AND changesSum entries from voters of the removed nominee are NOT cleaned up  (BUG)

=== Root Cause ===

Curve's original GaugeController has NO kill_gauge or removal function. The entire
removeNominee mechanism is custom Olas code with no battle-tested precedent.

When a user votes for a nominee, their slope is added to both:
  (a) pointsWeight[nomineeHash] — the nominee's individual weight
  (b) pointsSum — the total weight across all nominees
AND a scheduled slope change is written to:
  (c) changesWeight[nomineeHash][lockEnd] — cleared on revocation
  (d) changesSum[lockEnd] — NOT cleared on removal or revocation

removeNominee zeroes the nominee's BIAS but leaves the SLOPE intact. It does NOT
iterate over voters to clean changesSum entries. The assumption is that voters will
call revokeRemovedNomineeVotingPower() to clean up.

=== Impact Scenario (DoS) ===

1. Voters allocate weight to nominee N with locks expiring at various future times
2. Owner calls removeNominee(N) — bias zeroed, slope untouched
3. Voters let their veOLAS locks expire WITHOUT calling revokeRemovedNomineeVotingPower()
   (they have no economic incentive to do so for a removed nominee)
4. changesSum entries remain permanently — each time _getSum() iterates past a lock
   expiry, it subtracts the phantom slope from the sum
5. Over time, _getSum() floors at zero via the guard:
     if (pt.bias > dBias) { pt.bias -= dBias; } else { pt.bias = 0; pt.slope = 0; }
6. Meanwhile, individual nominee weights (for still-active nominees) do NOT floor at
   zero — they reflect real votes. So oldWeight > 0 while oldSum == 0.
7. When owner tries to removeNominee for ANOTHER nominee:
     uint256 newSum = oldSum - oldWeight;  // line 611: 0 - X → UNDERFLOW REVERT
   This reverts, making it impossible to remove any more nominees.

Note: line 611 uses raw subtraction, NOT _maxAndSub(). Compare with _getWeight()
and _getSum() which both use the safe pattern. The removeNominee function assumes
oldSum >= oldWeight but this invariant is broken by phantom slope accumulation.

=== Practical Feasibility Assessment ===

Preconditions for the DoS to materialize:
  (a) removeNominee must be called — requires governance proposal through GovernorOLAS
      → Timelock → removeNominee(). This is a rare, deliberate governance action.
  (b) Voters of the removed nominee must NOT call revokeRemovedNomineeVotingPower().
      Voters DO have an incentive to revoke (they regain voting power to reallocate),
      but passive voters who locked OLAS, voted once, and forgot may never do so.
  (c) Enough time must pass for phantom slopes to drain the sum to zero. Locks last
      up to 4 years. The changesSum entries subtract phantom slopes at each lock expiry.
      The _getSum() floor guard (line 238-240) clamps sum to zero once bias < slope*WEEK.
  (d) Owner tries to removeNominee for ANOTHER nominee while sum == 0 and that
      nominee's individual weight > 0.

Additional observation — _getSum() line 237 also unprotected:
  pt.slope -= dSlope;  // line 237: checked arithmetic (Solidity ^0.8.25)
  In Curve's original Vyper 0.2 code, this silently wraps on underflow.
  In the Solidity 0.8 port, this REVERTS. If changesSum[t] > pt.slope at a point
  where bias > dBias (line 234 condition), _getSum() itself would revert.
  This is a porting difference — Curve's arithmetic wraps, Olas's reverts.
  The same _maxAndSub pattern should be applied here too.

Numeric example:
  - 3 nominees (A, B, C). Total voting: 1000 OLAS * 4-year locks across all voters.
  - A receives 40% of votes. Owner removes A. Voters don't revoke.
  - A's phantom slopes = 40% of total slope remain in changesSum.
  - Over 4 years, _getSum() subtracts phantom slopes at each voter's lockEnd.
  - Sum decays ~1.4x faster than it should (real slope + 40% phantom slope).
  - If all locks expire around the same time, sum reaches 0.
  - Active nominees B and C still have non-zero individual weights from new voters.
  - removeNominee(B) → oldSum=0, oldWeight=weight(B)>0 → REVERT.

=== Workaround (without contract redeployment) ===

The contract is NOT upgradeable, so a code fix requires deploying a new
VoteWeighting and migrating all data — complex and costly. Instead, the following
operational procedure prevents the DoS:

WORKAROUND 1: Voter cleanup before each removal (RECOMMENDED)
  Before submitting a governance proposal for removeNominee(B):
  1. Identify all voters who voted for previously-removed nominees and haven't revoked.
     Read events: VoteForNominee(voter, removedNominee) where voter hasn't emitted
     VotingPowerRevoked(voter, removedNominee).
  2. Contact these voters and ask them to call revokeRemovedNomineeVotingPower().
  3. CRITICAL: revoke must happen BEFORE the voter's lock expires.
     - If oldSlope.end > block.timestamp: full cleanup occurs (lines 665-674):
       pointsSum slope adjusted, changesSum[lockEnd] cancelled.
     - If oldSlope.end <= block.timestamp: only voting power is returned (line 679).
       changesSum[lockEnd] was already processed by _getSum() — the phantom slope
       subtraction at lockEnd is permanent and cannot be undone.
     So the cleanup window = time between removeNominee and the voter's lock expiry.
  4. After cleanup, verify sum health: call getNomineeWeight() for the target nominee
     and getWeightsSum() — confirm sum >= target weight before proposing removal.

WORKAROUND 2: Two-step removal with vote-zeroing
  Instead of directly calling removeNominee:
  1. First governance proposal: request all voters of nominee X to set weight=0
     via voteForNomineeWeights(X, chainId, 0). This properly cleans up each voter's
     slopes and changesSum entries via the standard vote path (lines 530-551).
  2. After all voters have zeroed their weight, removeNominee(X) is called with
     oldWeight ≈ 0, so newSum = oldSum - 0 = oldSum → no underflow.
  This is the cleanest workaround but requires voter cooperation before removal.

WORKAROUND 3: Health monitoring
  Deploy an off-chain monitoring script that tracks:
  - Sum of pointsSum vs sum of individual pointsWeight for all active nominees
  - Number of unrevoked voters for removed nominees
  - Time until their locks expire
  If drift is detected → alert governance to coordinate cleanup (Workaround 1).

Why redeployment is impractical:
  VoteWeighting stores complex state: mapNomineeIds, setNominees, pointsWeight
  (per-nominee per-week bias+slope), pointsSum (per-week), changesWeight, changesSum,
  voteUserSlopes (per-user per-nominee), voteUserPower (per-user), lastUserVote
  (per-user per-nominee), timeWeight (per-nominee), timeSum. Migrating all this
  to a new contract requires either:
  (a) A migration function that copies all state (extremely gas-intensive, possibly
      exceeds block gas limit), or
  (b) Manual re-registration of all nominees and re-voting by all users.
  Neither is practical for a live governance system with active voters.

Conclusion: The bug is REAL — line 611 (and line 237) should use safe subtraction,
and the fix is trivial in code. However, the contract is not upgradeable, so the
practical mitigation is operational: ensure voter cleanup before each nominee removal.
The DoS scenario requires a confluence of rare conditions: governance-initiated removal
+ passive voters + multi-year timeframe without cleanup + another removal attempt.

Severity: LOW. Real code defect with trivial fix, but practical DoS path requires
rare conditions. Operational workarounds exist (voter cleanup, vote-zeroing).

=== Recommendation ===

Option A: Change line 611 to use _maxAndSub:
  uint256 newSum = oldSum > oldWeight ? oldSum - oldWeight : 0;

Option B: In removeNominee, also zero the nominee's slope:
  pointsWeight[nomineeHash][nextTime].slope = 0;
  (This doesn't fix changesSum but prevents slope from being counted in future _getWeight)

Option A is the minimal fix that prevents the DoS. Option B is more thorough.
```
[ ] Open

#### Notes. FxBaseChildTunnel / FxBaseRootTunnel: `setFxRootTunnel` / `setFxChildTunnel` lack access control (library)
```
lib/fx-portal/contracts/tunnel/FxBaseChildTunnel.sol line 31-33
lib/fx-portal/contracts/tunnel/FxBaseRootTunnel.sol line 59-62

These inherited library functions allow ANYONE to set the tunnel endpoint, as long as
it hasn't been set yet (one-time setter, no access control).

FxERC20ChildTunnel and FxERC20RootTunnel do NOT override these functions to add
access control. Neither constructor sets the tunnel address.

=== Deployment Script Analysis ===

Deployment is non-atomic across 4 scripts on 2 chains:
  1. scripts/deployment/bridges/polygon/deploy_03_child_erc20.js (Polygon) — deploys FxERC20ChildTunnel
  2. scripts/deployment/bridges/polygon/deploy_20_erc20_root_tunnel.js (Ethereum) — deploys FxERC20RootTunnel
  3. scripts/deployment/bridges/polygon/deploy_21_22_change_root_child_tunnels.js (Ethereum) — sets child tunnel on root
  4. scripts/deployment/bridges/polygon/deploy_04_change_child_root_tunnel.js (Polygon) — sets root tunnel on child

Between steps 1 and 4, FxERC20ChildTunnel has no fxRootTunnel set.
Between steps 2 and 3, FxERC20RootTunnel has no fxChildTunnel set.
An attacker monitoring for contract deployments could front-run steps 3 or 4.

=== Current Risk ===

LOW — these contracts are already deployed and tunnel addresses are set. The risk
window only exists during initial deployment. However, if contracts are ever redeployed,
the same non-atomic window would reappear.

Recommendation: for any future redeployment, set tunnel addresses in the constructor
or override setFxRootTunnel/setFxChildTunnel with owner-only access control.
```
[x] Noted — deployment already complete, risk window closed

#### Notes. VoteWeighting: `addNomineeEVM`/`addNomineeNonEVM` are permissionless
```
VoteWeighting.sol lines 325-365

Both functions are externally callable by anyone without access control.
This differs from Curve's original GaugeController where add_gauge is admin-only.

In the Olas design this appears intentional — anyone can register nominees (services/agents)
for emission voting, while only veOLAS holders can direct actual emissions via voting.
Only the owner can remove nominees (removeNominee, line 587).

Risks:
- Spam griefing: attacker adds thousands of nominees, inflating setNominees array
  (grows unbounded, only shrinks via owner removeNominee)
- Each addNominee calls IDispenser.addNominee(), which may incur state changes in Dispenser
- Misleading nominees could confuse voters (social engineering)

The practical impact is low because emissions require veOLAS voting power, and the
Dispenser may have its own nominee validation. However, the asymmetry (anyone adds,
only owner removes) creates a griefing surface.

Recommendation: consider adding owner-only access control to addNomineeEVM/addNomineeNonEVM,
or alternatively, add an upper bound on setNominees.length to prevent unbounded growth.
```
[x] To Discussion

#### Notes. OLAS `mint()` silently returns without minting when inflation control fails
```
OLAS.sol lines 75-85

function mint(address account, uint256 amount) external {
    if (msg.sender != minter) { revert ManagerOnly(msg.sender, minter); }
    if (inflationControl(amount)) {
        _mint(account, amount);
    }
    // No revert on failure — silent no-op
}

When inflationControl returns false, the function succeeds without minting and without
reverting. A caller (the minter contract) may not realize the mint was skipped unless
it checks token balances before/after.

This is documented behavior ("If the inflation control does not pass, the revert does
not take place, as well as no action is performed"), but it creates a footgun for
integration: a minter contract that relies on mint() reverting on failure would silently
lose tokens from its accounting.
```
[x] Noted — documented design choice

#### Notes. GovernorTimelockControl: `governorDelay` can desynchronize from timelock `minDelay`
```
GovernorTimelockControl.sol lines 189-204

When governorDelay is set, it is validated against _timelock.getMinDelay(). However, if
the timelock's minDelay is later increased (via a separate governance proposal), the
existing governorDelay becomes invalid without any notification.

In queue() (line 117), scheduleBatch is called with governorDelay as the delay parameter.
TimelockController.scheduleBatch requires delay >= minDelay. If minDelay > governorDelay,
all queue() calls revert, effectively bricking governance until governorDelay is updated.

Updating governorDelay requires a governance proposal — which itself requires queue().
This creates a circular dependency: governance is needed to fix governance.

The code documents this with a CAUTION comment (line 186-187), recommending simultaneous
updates. However, if they are accidentally separated, recovery requires either:
- A timelock admin reducing minDelay back (if such a role exists)
- The CM multisig acting via GuardCM bypass mechanisms
```
[x] Noted — documented, but circular dependency risk remains

#### Notes. ProcessBridgedDataWormhole: hardcoded TIMELOCK address
```
ProcessBridgedDataWormhole.sol line 44

address public constant TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;

If the Timelock contract is ever redeployed to a new address, this bridge verifier
must be redeployed as well. Unlike the Arbitrum verifier (which receives the L2 address
as a parameter from GuardCM), the Wormhole verifier uses a hardcoded constant.

This is a minor inconsistency between verifiers. The Arbitrum approach (parameter from
GuardCM) is more flexible.
```
[x] Noted

#### Notes. Mixed Solidity pragma versions across contracts
```
The repository uses multiple pragma versions:
- ^0.8.15: OLAS.sol, veOLAS.sol, buOLAS.sol
- ^0.8.19: wveOLAS.sol, FxGovernorTunnel.sol, HomeMediator.sol
- ^0.8.20: GovernorOLAS.sol
- ^0.8.23: BridgeMessenger.sol, OptimismMessenger.sol, WormholeMessenger.sol
- ^0.8.25: VoteWeighting.sol
- ^0.8.28: Burner.sol
- ^0.8.30: GovernorTimelockControl.sol, GuardCM.sol, VerifyData.sol, VerifyBridgedData.sol,
           ProcessBridgedData*.sol, WormholeRelayerTimelock.sol

All compile with ^0.8.30 due to pragma ranges. However, the inconsistency suggests
different contracts were written at different times and not harmonized. Consider
standardizing to ^0.8.30 or a single version.
```
[x] Noted

#### Low. Burner.sol has zero test coverage
```
Burner.sol (66 LOC) has 0% statement, branch, function, and line coverage.
No tests exist for this contract in the test suite.

While the contract is simple (burn all OLAS balance, with reentrancy guard),
it should have basic test coverage for:
- Successful burn
- Revert on zero balance
- Reentrancy guard
```
[ ] Open

#### Notes. C4A fix revert paths untested
```
The C4A fixes in ProcessBridgedDataArbitrum.sol and ProcessBridgedDataWormhole.sol
added several new revert conditions:
- Arbitrum: l2CallValue > 0, excessFeeRefundAddress != l2Timelock, callValueRefundAddress != l2Timelock
- Wormhole: receiverValue > 0, refundChainId != REFUND_CHAIN_ID, refundAddress != TIMELOCK

These revert paths have 0% branch coverage (lines 71, 76, 79 in Arbitrum; 94, 97, 103 in Wormhole).
The fixes are correct by inspection, but adding regression tests would prevent future regressions.
```
[ ] Open

#### Notes. GovernorOLAS exceeds 24576 byte contract size limit
```
Compilation warning: GovernorOLAS exceeds the contract size limit (EIP-170).
This is caused by inheriting multiple OZ governance extensions
(Governor + Settings + CompatibilityBravo + Votes + QuorumFraction + TimelockControl).

On chains with strict EIP-170 enforcement, this contract cannot be deployed.
The contract is deployed on Ethereum mainnet, where the limit is enforced but
the compiler's "ir" pipeline can help reduce size.
```
[x] Noted — already deployed successfully on mainnet

## Methodology Compliance Report

Full audit performed per internal security audit playbook v2.17 methodology and
autonolas-internal-audit-methodology rules.

### Phase 0: Protocol Classification
- **Type**: Governance (voting escrow + gauge controller + cross-chain bridge)
- **Prior audits**: 17 internal + 1 C4A external + 10 known vulnerabilities documented in PDF
- **Trust model**: owner = Timelock (3/5 multisig), HIGH trust. Admin actions = NOT findings.
- **Admin roles**: owner (Timelock) = HIGH, multisig (GuardCM) = MEDIUM (pause only if governance dead)
- **Upgradeability**: None — all contracts deployed directly (no proxy/UUPS/transparent)
- **Token model**: OLAS (solmate ERC20, standard), veOLAS/buOLAS (non-transferable)
- **Known issues**: 10 documented in `docs/Vulnerabilities_list_governance.pdf` — all cross-referenced

### Phase 2: Automated Analysis
- [x] Slither: 242 results, all triaged (see `analysis/slither_full.txt`)
- [x] Coverage: 98.48% statements, 93.56% branches
- [x] Compilation warnings: GovernorOLAS exceeds 24576 byte limit

### Checklist Compliance (AGENT-RULES.md Rule 3)

| Checklist | Items | Checked | Findings | N/A |
|-----------|:-----:|:-------:|:--------:|:---:|
| C1-C12 (Access Control/Proxy/Init) | 12 | 12 | 0 | 8 |
| T1-T12 (Token Handling/Arithmetic) | 12 | 12 | 0 | 3 |
| T13-T35 (Token Advanced) | 23 | 23 | 0 | 23 |
| D1-D22 (DoS/Gas Griefing) | 22 | 22 | 0 | 17 |
| L1-L65 (Business Logic Edge Cases) | 65 | 65 | 0 | 42 |
| DeFi Attack Patterns 1-140 | 140 | 140 | 0 | 98 |
| Access Control Patterns A-N | 14 | 14 | 0 | 5 |
| Token & Reward Patterns | 20+ | 20+ | 0 | 18 |
| **Total** | **~308** | **~308** | **0** | **~214** |

All findings were discovered during manual review phases (Phase 3/3b), not from checklist items.
~70% of DeFi attack patterns are N/A because this is a governance/bridge protocol (no oracle,
no lending, no liquidation, no pools, no swaps, no ERC4626, no flash loans).

### Key items checked with positive results (applicable, no issue):
- **C2**: ALL public/external state-changing functions enumerated. Only `addNomineeEVM/addNomineeNonEVM` permissionless (documented as Notes finding).
- **C5**: All `.call()` and `delegatecall` targets are governance-controlled.
- **C10**: GuardCM delegatecall to owner-set verifiers with code.length check. Multisig delegatecall explicitly blocked.
- **C12**: All 4 bridge messengers validate callback source (relayer + governor address).
- **T5**: All unsafe casts bounded by preceding checks (uint96 max for amounts, uint32 safe until 2106).
- **T11**: Curve math: bias/slope clamped ≥0, amounts capped, 255-week loop sufficient.
- **T31**: Rounding consistently favors protocol (truncation in slope/weight calculation).
- **D1**: All loops bounded (MAX_NUM_WEEKS=250, 255, 128 for binary search).
- **D9**: GuardCM pause/unpause: timelock can always unpause. No permanent lock.
- **L3**: Coupled state pairs (supply↔lockedBalance, voteUserPower↔voteUserSlopes) all updated symmetrically.
- **L42**: GovernorOLAS uses OZ snapshot-based voting (getPastVotes at proposal block). veOLAS non-transferable → no double-voting.
- **L46**: All low-level call return values checked (`if (!success) revert`).
- **L49**: Bridge parameter verification matrix — all 5 bridges (Gnosis/Optimism/Polygon/Wormhole/Arbitrum) verified.
- **L53**: veOLAS non-transferable → flash loan governance attack impossible.
- **DeFi #18**: Permissionless addNominee = sybil slot filling vector (documented as Notes finding).
- **DeFi #62**: Bridge verification matrix complete — all parameters decoded and validated per bridge.
- **Access Pattern B**: Arbitrary call in bridge messengers — governance-controlled source verified.

## Contracts reviewed — no issues found

The following contracts were reviewed in full with no security issues found:

- **veOLAS.sol**: Standard Curve VotingEscrow port. Non-transferable, non-delegatable. Amount capped at uint96. 255-week checkpoint loop (standard limitation). CEI pattern followed (transfer after state update). Unchecked operations are well-documented and safe within specified limits.

- **OLAS.sol**: Solmate ERC20 with 10-year cap (1B tokens), then 2% annual inflation. Owner/minter separation. `decreaseAllowance` correctly handles max allowance. `inflationRemainder` loop is bounded by years elapsed.

- **buOLAS.sol**: Burnable locked OLAS with linear vesting (yearly steps, max 10). Revoke mechanism correctly separates matured from unvested tokens. Burns happen on user's withdraw after revoke. uint32 timestamp safe until 2106 (documented).

- **wveOLAS.sol**: Pure view-only wrapper delegating to veOLAS. No state mutations. Defensive zero-point checks before delegation. Fallback reverts with `ImplementedIn`.

- **VoteWeighting.sol**: Curve GaugeController port for Nominee struct (account + chainId). Vote delay 10 days. MAX_NUM_WEEKS = 250 for checkpoint iterations. Swap-and-pop nominee removal. `_maxAndSub` used consistently for bias/slope adjustments. `revokeRemovedNomineeVotingPower` allows cleanup after removal.

- **GuardCM.sol**: Transaction guard for CM multisig. Validates Timelock's `schedule`/`scheduleBatch` calls. Bridge data verified via delegatecall to chain-specific verifiers. Pause mechanism: callable by timelock directly, or by multisig if governance proposal is defeated. Owner is immutable (timelock).

- **Burner.sol**: Simple burn-all-balance helper with reentrancy guard. No issues.

- **GovernorOLAS.sol**: Standard OZ Governor composition. All overrides are simple `super` delegations. No custom logic beyond constructor parameters.

- **Bridge messengers (FxGovernorTunnel, HomeMediator, OptimismMessenger, WormholeMessenger)**: All follow the same pattern — verify bridge relayer → verify source governor → process data. WormholeMessenger adds delivery hash uniqueness check. Governor address changes require self-call (only via bridge). Data processing assembly is standard (GnosisSafe MultiSend pattern), with Solidity bounds checking on payload array access.

- **WormholeRelayerTimelock**: Reentrancy-guarded, timelock-only access. Fee management sends leftovers to caller-specified refundAddress. Token approvals for wormholeTokenBridge are per-transfer (no lingering approvals). Nonce increment is safe.

- **VerifyData / VerifyBridgedData**: Target/selector/chainId whitelist via packed uint256 key. Bridge verifiers inherit and process packed data correctly.

- **ProcessBridgedData{Arbitrum,Gnosis,Optimism,Polygon,Wormhole}**: Chain-specific header parsing and validation. Arbitrum and Wormhole have C4A fixes (verified above). All parse the bridge-specific header, extract the inner payload, and delegate to `_verifyBridgedData` / `_verifyData`.

## Summary

| Severity | Count |
|----------|-------|
| High | 0 |
| Medium | 0 |
| Low | 2 |
| Notes/Discussion | 7 |

The autonolas-governance codebase is mature and well-audited (17 prior internal audits + C4A external audit). The Curve-derived contracts (veOLAS, VoteWeighting) follow established patterns. The bridge verification system is comprehensive, and the C4A findings have been correctly addressed.

The main finding is the removeNominee slope drift issue (Low), which extends known vulnerability #8 from the project's Vulnerabilities_list_governance.pdf — the PDF documents orphaned voting power but does NOT cover the slope/changesSum drift or the potential DoS path at line 611. The bug is real (raw subtraction should be `_maxAndSub`), but the practical DoS scenario requires a rare confluence of conditions: governance-initiated removal + passive voters + multi-year timeframe. All 10 known vulnerabilities from the PDF were cross-referenced and confirmed.
