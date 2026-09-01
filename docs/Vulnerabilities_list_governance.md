# Contracts vulnerabilities

## Vulnerabilities list

| # | Vulnerability | Severity |
|---|---|---|
| 1 | [getPastVotes function](#1-getpastvotes-function) | Low |
| 2 | [balanceOfAt function](#2-balanceofat-function) | Low |
| 3 | [_checkpoint function](#3-_checkpoint-function) | Medium |
| 4 | [createLockFor function](#4-createlockfor-function) | Medium |
| 5 | [totalSupplyLockedAtT function](#5-totalsupplylockedatt-function) | Low |
| 6 | [getPastTotalSupply function](#6-getpasttotalsupply-function) | Low |
| 7 | [processMessageFromForeign function](#7-processmessagefromforeign-function) | Informative |
| 8 | [removeNominee function](#8-removenominee-function) | Medium |
| 9 | [_addNominee and removeNominee functions](#9-_addnominee-and-removenominee-functions) | Informative |
| 10 | [voteForNomineeWeights function](#10-votefornomineeweights-function) | Informative |
| 11 | [removeNominee OwnerOnly revert-data argument order](#11-removenominee-owneronly-revert-data-argument-order) | Informative |
| 12 | [OLAS mint silent no-op on inflation cap](#12-olas-mint-silent-no-op-on-inflation-cap) | Informative |
| 13 | [governorDelay and timelock minDelay desynchronization](#13-governordelay-and-timelock-mindelay-desynchronization) | Informative |
| 14 | [VoteWeighting addNomineeEVM and addNomineeNonEVM are permissionless](#14-voteweighting-addnomineeevm-and-addnomineenonevm-are-permissionless) | Informative |
| 15 | [ProcessBridgedDataWormhole hardcoded TIMELOCK constant](#15-processbridgeddatawormhole-hardcoded-timelock-constant) | Informative |
| 16 | [GuardCM setTargetSelectorChainIds does not bound chainId](#16-guardcm-settargetselectorchainids-does-not-bound-chainid) | Informative |
| 17 | [Cross-chain verifiers do not bound the per-record native value](#17-cross-chain-verifiers-do-not-bound-the-per-record-native-value) | Low |
| 18 | [VoteWeighting _nomineeRelativeWeight not capped at 1e18](#18-voteweighting-_nomineerelativeweight-not-capped-at-1e18) | Low |
| 19 | [VoteWeighting removeNominee last-element guard mismatch](#19-voteweighting-removenominee-last-element-guard-mismatch) | Informative |
| 20 | [VoteWeighting revokeRemovedNomineeVotingPower missing checkpoint advance](#20-voteweighting-revokeremovednomineevotingpower-missing-checkpoint-advance) | Informative |
| 21 | [GuardCM mapBridgeMediatorL1BridgeParams keyed by L1 address only](#21-guardcm-mapbridgemediatorl1bridgeparams-keyed-by-l1-address-only) | Informative |
| 22 | [WormholeMessenger single sourceGovernor authentication](#22-wormholemessenger-single-sourcegovernor-authentication) | Informative |
| 23 | [Timelock deployer-EOA admin bootstrap window](#23-timelock-deployer-eoa-admin-bootstrap-window) | Informative |
| 24 | [FxERC20RootTunnel setFxChildTunnel is a permissionless one-shot](#24-fxerc20roottunnel-setfxchildtunnel-is-a-permissionless-one-shot) | Informative |
| 25 | [Unbounded Governor settings and unchecked Timelock replacement can permanently brick governance](#25-unbounded-governor-settings-and-unchecked-timelock-replacement-can-permanently-brick-governance) | Medium |
| 26 | [VoteWeighting catch-up cursors do not advance across a multi-year gap](#26-voteweighting-catch-up-cursors-do-not-advance-across-a-multi-year-gap) | Informative |
| 27 | [Nominees can be added for chains that cannot receive incentives](#27-nominees-can-be-added-for-chains-that-cannot-receive-incentives) | Informative |

## Involved contracts and level of the bugs

The present document aims to point out some vulnerabilities in the contracts veOLAS,
buOLAS, and VoteWeighting. Some of these vulnerabilities may lead to critical[^1] bugs.

## Vulnerabilities

### 1. `getPastVotes` function

**Acknowledgments:** This vulnerability was discovered thanks to [howd4ys](https://immunefi.com/) who kindly
reported it by participating in the [Autonolas Immunefi Bug Program](https://immunefi.com/).

**Severity:** Low[^2]

In the veOLAS contract, the following function is implemented:

```solidity
function getPastVotes(address account, uint256 blockNumber) public view override returns (uint256 balance)
```

This function returns the voting power of the address `account` at a specific `blockNumber`.

This function has an incorrect behavior when the input `blockNumber` is smaller than the
block number `n` where a lock was first created for the `account`.

Specifically, denoting by `T` the timestamp of the input `blockNumber` and `T1` the
timestamp of the block `n`, the incorrect behavior arises because of the subtraction
veOLAS.sol#L680 that becomes an addition when `blockTime=T` is smaller than
`uPoint.ts=T1`. Denoting by `T2` the `endTime` for the locking created for the `account` at
time `T1`, the calculation in veOLAS.sol#L680 provides the following value for the bias
`bias=slope*(T2-T)`. However, the latter bias is bigger than the correct value for the
bias at the timestamp `T1` which should be `slope*(T2-T1)`.

We recommend using as an input parameter of the function a `blockNumber` bigger than
the block number `n` where a lock was first created for the `account`.

Note that the function `getPastVotes(account,blockNumber)` is used to weigh the
voting power of users that cast a vote on a governance proposal. Whether there is a
governance proposal and a user creates a lock after the beginning and no later than the
end of the voting period, due to this vulnerability of
`getPastVotes(account,blockNumber)`, the user would be able to cast a voting power
bigger than its correct one. Note that the manipulation of the voting power has an upper
bound due to the fact that there is a limited number of blocks in a voting period and that
any locks last at least one week. Nevertheless, currently, there is no possibility of creating
new locks, so this issue cannot affect any governance voting.

The wrapped veOLAS (wveOLAS) contract wraps original veOLAS view functions and
serves as mitigating measures to address this issue.

### 2. `balanceOfAt` function

**Severity:** Low[^3]

In the veOLAS contract, the following function is implemented:

```solidity
function balanceOfAt(address account, uint256 blockNumber) external view returns (uint256 balance)
```

This function returns the actual balance of the address `account` at a specific `blockNumber`.

This function has an incorrect behavior when the input `blockNumber` is smaller than the
block number `n` where a lock was first created for the `account`.

As for the previous vulnerability explanation (`getPastVotes()`), the function
`balanceOfAt()` uses the same binary search algorithm followed by identical value
extraction, and thus returns a very first balance of a locked point, whereas it should return
zero.

We recommend using `blockNumber` input parameter value bigger than the block number
`n` where a lock was first created for the `account`.

The wrapped veOLAS (wveOLAS) contract wraps original veOLAS view functions and
serves as mitigating measures to address this issue.

### 3. `_checkpoint` function

**Severity:** Medium[^4]

In the veOLAS contract, the following function is implemented:

```solidity
function _checkpoint(address account, LockedBalance memory oldLocked, LockedBalance memory newLocked, uint128 curSupply) internal
```

According to the article on [medium.com](https://medium.com), the declaration of a memory struct *lastPoint* and
its assignment to another memory struct leads to the pointer of the initial struct, and not
its deep copy, that can be observed in line 219. This leads to the incorrect calculations of
history points for the periods of time when there was no *checkpoint()* function called for
more than a week.

However, there is more to the specified issue that leads to following observations:

- If the contract has not created a user point during a specific week, then when
  finally created, the internal checkpoint function writes a point in that week with the
  block number equal to the last created point but with a timestamp equal to the end
  time of the week that has just passed. If no points were created for several weeks,
  then the internal checkpoint function recreates a point for each week of inactivity
  having the block number equal to the last created user point and the timestamp
  equal to the end time of the end of each skipped week.
- Even if the checkpoint is called once a week, two points are created: one point
  with a block number equal to the last created point but with a timestamp equal to
  the end time of the week, and another one with an actual block number and
  corresponding timestamp of the checkpoint call.

This behavior leads to the creation of supply points that have an incorrect block number
detached from the actual timestamp. This further leads to the scenario where all supply
points during the weeks of inactivity of veOLAS have the same block numbers as the first
point that triggered the *checkpoint()*. In other words, all the supply points that were
recreated at the end time of every week will not be correctly recovered during the block
number search (via the block number itself or the timestamp). Any historic lookups
between two supply points (not including points themselves) that were created
immediately before and immediately later the exact end of a week or that were created
with more than a week of inactivity will have an incorrect block number equal to the one
of a first point.

This might potentially affect the voting functionality. If the voting was performed during
the time that had to account for the inactivity weeks, immediately after the very last point
before the end time of a week, or immediately after an eventful point was created at the
end time of a week, the weighted total supply (the overall number of votes) in the function
*getPastTotalSupply()* **might** return incorrect values (depending on the first point with the
same block number found via a binary search).

In the absence of deploying new contracts, we recommend running the analogue of the
cron scheduler / service that checks for the veOLAS activity during the week, and if there
was none, trigger a *checkpoint()* function call immediately before and immediately after
end time of each week. This way, all the supply points will be updated throughout the time
of the contract and, we increase the likelihood of having voting periods starting
immediately after and before effective points with different blocks timestamps (not in the
weekly time divider). As the protocol becomes more active, this issue will be minimized by
the participation of DAO members.

To minimize a possible impact, the service triggering the *checkpoint()* call must be
executed as close to the whole week of unix time as possible. Specifically, if the
checkpoint is called at least once a week, a possible deviation in the total voting supply
can only happen if the vote starts after the very last point of week (not in the weekly time
divider) or before the very first point of a week. The supply deviation factor depends on
the time difference between the very last weekly point (not in the weekly end divider) and
the very first point after the weekly end time divider point.

Therefore, calling checkpoints as closer to the end and the beginning of the week of unix
time as possible the supply deviation can be minimized. A probabilistic analysis of how
likely such a scenario can happen is out of the scope of this document. However, despite
its likelihood, it is worth mentioning that, even in such a scenario, there is no certainty that
the wrong point will be picked by the binary search and ultimately there is no certainty
that the issue is going to affect the expected result.

### 4. `createLockFor` function

**Severity:** Medium

In veOLAS and buOLAS contracts, the following function is implemented:

```solidity
function createLockFor(address account, uint256 amount, uint256 unlockTime) external
```

This function allows anyone, even a smart contract, to create a lock for a third-party
`account`. If the third-party `account` has already a locked amount the call will be reverted.
If not and the OLAS amount provided as input is non-zero then a lock is created.

As a consequence, any third-party account can be forced into a long lock length (for a
maximum of 4 years for veOLAS and 10 years for buOLAS) by an attacker calling
`createLockFor` with a very small amount of OLAS (i.e. 1/10^18) and a max lock length.
An attacker could use this to prevent locks over a given adversarially chosen interval by
front-running all locks in this manner. All accounts with an intent to lock for less than 4
years would be affected. We assign a low likelihood to this attack, as it is not
economically profitable for the attacker.

Indeed, the caller of the `createLockFor` function can lock for third-party users only by
using its own OLAS tokens. So the mintable OLAS tokens can be temporarily frozen only
with an attacker's extensive cost.

In the buOLAS contract, there is also an extra guardrail that can be considered. If the
attack has been discovered, it is possible to invoke a governance vote to revoke the
unvested OLAS of the third-party account that has been forced in a long lock into
buOLAS. If the governance approves the revoke, the third-party account can call the
buOLAS withdraw function, and all non-vested OLAS tokens will be burned. When the
withdrawal function is called less than one year after the attack, all the contract status
can return to their original status before the attack has been made.

### 5. `totalSupplyLockedAtT` function

**Severity:** Low

In the veOLAS contract, the following function is implemented:

```solidity
function totalSupplyLockedAtT(uint256 ts) public view returns (uint256)
```

The function is used solely by the `totalSupplyLocked()` function with the current
`block.timestamp`. By the original design, it is not intended to have a `ts` parameter
smaller than the current `block.timestamp`.

We recommend not to call this function for any external purposes. It is a view function
that is not currently used externally in any of Autonolas on-chain protocol contracts, and
thus does not affect any intended behavior.

The wrapped veOLAS (wveOLAS) contract wraps original veOLAS view functions and
serves as mitigating measures to address this issue.

### 6. `getPastTotalSupply` function

**Severity:** Low

In the veOLAS contract, the following function is implemented:

```solidity
function getPastTotalSupply(uint256 blockNumber) external view returns (uint256)
```

The function returns the voting power of a specified block number. However, by the
original implementation, the requested block number must be at least equal to the zero
supply point block number, or the block number of a contract deployment. Otherwise, the
function reverts instead of returning a zero value.

We recommend not to call this function with the input block number value less than a zero
supply point block number, since it is meaningless anyway as there must be no values
before the very first supply point is created in the contract.

### 7. `processMessageFromForeign` function

**Severity:** Informative

In the HomeMediator contract, the following function is implemented:

```solidity
function processMessageFromForeign(bytes memory data) external
```

The role of HomeMediator contract is to execute actions based on governance proposals
originating from Ethereum. This execution is rigorously bound to governance decisions,
with the validation of the message sender being restricted to the Timelock address on
Ethereum.

In the current implementation, the `processMessageFromForeign()` method ensures
that the `msg.sender` aligns with the Ethereum Timelock address. However, it does not
enforce a verification of the source `chainId` to match Ethereum's `chainId`. This poses
no immediate issues as the arbitrary message bridge contract, facilitating communication
between Ethereum and Gnosis, exclusively processes requests from the Ethereum chain.

For future scenarios where the arbitrary message bridge contract might handle requests
from diverse chains (as outlined in the [doc](https://docs.gnosischain.com/)), it is recommended to improve the
implementation of HomeMediator's `processMessageFromForeign()` method by
incorporating a `chainId` check.

### 8. `removeNominee` function

**Severity:** Medium

> Raised from **Low** to **Medium** in the internal21 fix-verification round. The original label
> was set against the orphaned-voting-power reading of this entry; the accounting defect documented
> below is a permanent checkpoint DoS — once triggered, the weekly `_getSum()` walk reverts and
> `nomineeRelativeWeightWrite` (and with it the Dispenser reward-distribution path) halts, with no
> recovery short of redeployment. Medium reflects that impact.

In the VoteWeighting contract, the following function is implemented:

```solidity
function removeNominee(bytes32 account, uint256 chainId) external
```

The `removeNominee()` function is designed to remove a nominee from the system. This
operation is restricted to the contract owner.

Whether the nominee exists, the nominee's current weight is then set to zero for the next
checkpoint time. The total weight sum is updated to reflect the removal of the nominee's
weight. If a dispenser contract is configured, the function calls the `removeNominee`
method on the dispenser to ensure this is aware of the removal.

If a nominee is removed and users have allocated non-zero weight to that nominee, the
associated voting power becomes orphaned. The contract doesn't automatically retrieve
or reallocate user voting power within the `removeNominee()` function itself. However,
users can reclaim their voting power using the
`revokeRemovedNomineeVotingPower()` function. It's advisable for voters to update
a non-zero weight of their nominee to zero before the nominee's removal is expected to
happen or to reclaim their vote after the nominee's removal has occurred.

Additionally, when a nominee is removed, the last nominee in the set will take the place of
the removed nominee, changing its ID at the end of the `removeNominee()` call. It's
important to note that the same ID can correspond to different nominees at different
times, depending on removals.

Beyond orphaned voting power, `removeNominee()` has a deeper accounting defect
related to slope and `changesSum` cleanup. When a user votes for a nominee, their slope is
added to both:
- `pointsWeight[nomineeHash]` — the nominee's individual weight;
- `pointsSum` — the total weight across all nominees.

And a scheduled slope change is written to:
- `changesWeight[nomineeHash][lockEnd]` — cleared on revocation;
- `changesSum[lockEnd]` — NOT cleared on removal or revocation

`removeNominee()` zeroes the nominee's bias but leaves the slope intact
(VoteWeighting.sol lines 603–613). It does NOT iterate over voters to clean `changesSum`
entries. The assumption is that voters will call `revokeRemovedNomineeVotingPower()`
to clean up.

**Impact scenario (DoS):**

1. Voters allocate weight to nominee N with locks expiring at various future times.
2. Owner calls `removeNominee(N)` — bias zeroed, slope untouched.
3. Voters let their veOLAS locks expire WITHOUT calling
   `revokeRemovedNomineeVotingPower()` (they have no strong economic
   incentive to do so for a removed nominee).
4. `changesSum` entries remain permanently — each time `_getSum()` iterates past a
   lock expiry, it subtracts the phantom slope from the sum.
5. Over time, `_getSum()` floors at zero via the guard:
   `if (pt.bias > dBias) { pt.bias -= dBias; } else { pt.bias = 0; pt.slope = 0; }`.
6. Meanwhile, individual nominee weights (for still-active nominees) do NOT floor at
   zero — they reflect real votes. So `oldWeight > 0` while `oldSum == 0`.
7. When owner tries to `removeNominee()` for another nominee:
   `uint256 newSum = oldSum - oldWeight; // line 611: 0 - X → UNDERFLOW REVERT`
8. This reverts, making it impossible to remove any more nominees.

`_getSum()` line 237 is also unprotected: `pt.slope -= dSlope;`
If `changesSum[t] > pt.slope` at a point where `bias > dBias`, `_getSum()` itself
would revert.

**Practical feasibility:**

- `removeNominee()` requires a governance proposal through GovernorOLAS →
  Timelock — a rare, deliberate action.
- Voters of the removed nominee must NOT call
  `revokeRemovedNomineeVotingPower()`. Voters do have some incentive to
  revoke (they regain voting power to reallocate), but passive voters who locked
  OLAS, voted once, and forgot may never do so.
- Enough time must pass for phantom slopes to drain the sum to zero (locks last up
  to 4 years).
- Owner tries to `removeNominee()` for another nominee while `sum == 0` and that
  nominee's individual `weight > 0`.

**Workarounds (without contract redeployment):**

1. **Voter cleanup before each removal (recommended):** Before submitting a
   governance proposal for `removeNominee(B)`, identify all voters who voted for
   previously-removed nominees and haven't revoked (read `VoteForNominee` /
   `VotingPowerRevoked` events). Contact these voters and ask them to call
   `revokeRemovedNomineeVotingPower()`. Note that revoke must happen
   BEFORE the voter's lock expires — if `oldSlope.end > block.timestamp`, full cleanup
   occurs; if the lock already expired, the `changesSum` entry was already processed
   and the phantom subtraction is permanent.
2. **Two-step removal with vote-zeroing:** Request all voters of nominee X to set
   `weight=0` via `voteForNomineeWeights(X, chainId, 0)` first, which properly
   cleans up slopes and `changesSum` via the standard vote path. Then
   `removeNominee(X)` with `oldWeight ≈ 0` avoids underflow.
3. **Health monitoring:** Deploy off-chain monitoring that tracks `pointsSum` vs. sum of
   individual `pointsWeight` for all active nominees, plus unrevoked voters for
   removed nominees and time until their locks expire.

**Status — addressed in the pending VoteWeighting redeployment.** `VoteWeighting` is not
upgradeable, so the accounting defect is fixed by redeploying the contract; the fix is
implemented and takes effect once the new VoteWeighting is deployed and adopted via
governance. In the redeployed contract `removeNominee()` reconciles the aggregate bias,
the still-active slope, and the removed nominee's future `changesSum` entries, so the
`_getSum()` underflow / checkpoint-DoS path is closed by construction rather than by
voter-cleanup discipline. The workarounds above apply only until the new contract is live.

### 9. `_addNominee` and `removeNominee` functions

**Severity:** Informative

In the VoteWeighting contract, the following functions are implemented:

```solidity
function _addNominee(Nominee memory nominee) internal
function removeNominee(bytes32 account, uint256 chainId) external
```

The `removeNominee()` function is designed to remove a nominee from the system, and
this operation is restricted to the contract owner. On the other hand, `_addNominee()`
adds a nominee to the system.

In both cases, if a Dispenser is configured, these functions respectively call the
`addNominee()` and `removeNominee()` methods on the dispenser contract. This ensures
that the dispenser is kept informed about any nominees being added or removed.

It's highly recommended for the deployer to set up a dispenser contract immediately after
deploying VoteWeighting and ensure that no nominees were added or removed before
that. This precaution helps prevent potential synchronization issues between nominees on
the VoteWeighting and Dispenser contracts.

### 10. `voteForNomineeWeights` function

**Severity:** Informative

In the VoteWeighting contract, the following function is implemented:

```solidity
function voteForNomineeWeights(bytes32 account, uint256 chainId, uint256 weight) public
```

The function is designed to allocate voting power for changing pool weights. Note that
following the original Curve implementation, the function reverts if the next time of
recording weights is equal to the end of veOLAS lock (reverts if `nextTime >= lockEnd`).
In case of equality, the voting account is not able to place their weights as
their veOLAS lock expires in a week. We consider this not to be an issue, as one week
of time results in a very low voting power addition, and the lock can always be extended
for longer in order to make a bigger weighting input.

### 11. `removeNominee` `OwnerOnly` revert-data argument order

**Severity:** Informative

In the `VoteWeighting` contract, the `OwnerOnly` custom error is declared as:

```solidity
/// @param sender Sender address.
/// @param owner  Required sender address as an owner.
error OwnerOnly(address sender, address owner);
```

Two of the three revert sites pass arguments in the declared order `(msg.sender, owner)` —
correct. The site inside `removeNominee` passes them in the reverse order:

```solidity
function removeNominee(bytes32 account, uint256 chainId) external {
    // Check for the contract ownership
    if (msg.sender != owner) {
        revert OwnerOnly(owner, msg.sender);   // arguments swapped
    }
    ...
}
```

**Impact.** Cosmetic / debug-info only. The `revert` fires for the correct condition and
execution behaviour is unaffected — an unauthorized caller still cannot remove a nominee.
However, any caller that decodes the revert data from `eth_call` simulations, Tenderly
traces, or incident-response tooling will observe:

- `sender` field populated with the contract's `owner` address (e.g., the Timelock);
- `owner` field populated with the unauthorized `msg.sender`.

i.e. the opposite of the declared semantics. This can confuse automated tooling or a
human reading a trace when triaging a failed `removeNominee` call.

**Status — addressed in the pending VoteWeighting redeployment.** `VoteWeighting` is not
upgradeable, so this is fixed by redeploying the contract. A redeploy is already being
carried out to close the entry #8 accounting defect; the `OwnerOnly(sender, owner)`
argument order is corrected in that redeployment and takes effect once the new contract is
deployed and adopted via governance.

**Mitigation / guidance for tooling.** Any tool that decodes `OwnerOnly` reverts
originating from `VoteWeighting` should be aware that when the revert originates from
`removeNominee` specifically, the two address fields are reported in reversed order
relative to the error declaration. The two other call sites
(`changeOwner`-style paths in the contract) report arguments in the declared order.
A simple defensive approach is to treat both `(a, b)` and `(b, a)` as valid sender/owner
pairings when decoding reverts from this contract, and to compare both candidates
against the known owner address. The two call sites that do report arguments in the
declared order are `changeOwner` and `changeDispenser`.

### 12. OLAS `mint` silent no-op on inflation cap

**Severity:** Informative

In the `OLAS` contract, the `mint()` function is implemented as:

```solidity
/// @notice If the inflation control does not pass, the revert does not take place,
///         as well as no action is performed.
function mint(address account, uint256 amount) external {
    // Access control
    if (msg.sender != minter) {
        revert ManagerOnly(msg.sender, minter);
    }

    // Check the inflation schedule and mint
    if (inflationControl(amount)) {
        _mint(account, amount);
    }
}
```

When the requested `amount` exceeds the current `inflationRemainder()`, the
`inflationControl(amount)` check returns `false`, the `_mint` call is skipped, and the
function returns successfully **without reverting** and **without minting any tokens**.

**Impact.** This is documented behaviour (see the natspec comment on the function), but
it creates an integration footgun for the `minter` contract:

- A minter contract that assumes "`mint()` either reverts or mints the full amount" can
  silently mis-account. For example, a Treasury/Depository that debits an internal
  balance before calling `mint()` and expects the call to revert on failure would end
  up with its internal balance and the actual OLAS `totalSupply` out of sync.
- The silent-success pattern provides no signal to the caller about which specific
  branch was taken (access-control revert vs. cap-hit no-op vs. successful mint).
- Tenderly traces and offline simulations that rely on "tx failed → something was
  wrong" will not flag a cap-hit call.

**Why this is not fixed.** The silent-no-op behaviour is a deliberate design choice,
documented in the function's natspec, to avoid bricking the minter contract at the
moment the cumulative inflation cap is reached. A `revert` at that boundary could force
a governance intervention to change the minter or migrate accounting — the silent
no-op lets the minter discover the cap-hit and handle it gracefully at the integration
layer. `OLAS` is also not upgradeable.

**Mitigation / guidance for integrators.** Any contract that calls `OLAS.mint()` should
**not** rely on `mint()` reverting when minting is refused. Instead, integrators should:

1. Call `inflationControl(amount)` or `inflationRemainder()` before `mint()` to
   pre-check the cap, or
2. Measure the `balanceOf` of the recipient before and after `mint()` and verify the
   delta matches the requested amount.

Do **not** pattern-match on "the tx did not revert" to conclude minting succeeded.

### 13. `governorDelay` and timelock `minDelay` desynchronization

**Severity:** Informative

The custom `GovernorTimelockControl` contract maintains its own `governorDelay` field,
which is passed as the `delay` argument to `TimelockController.scheduleBatch` in the
Governor's `queue()` override:

```solidity
function queue(address[] memory targets, ...) public virtual override returns (uint256) {
    ...
    uint256 delay = governorDelay;
    _timelock.scheduleBatch(targets, values, calldatas, 0, descriptionHash, delay);
    ...
}
```

`TimelockController.scheduleBatch` enforces that `delay >= getMinDelay()` on the
timelock itself. The `_updateGovernorDelay` internal setter guards against initial
misconfiguration by reverting if `newGovernorDelay < minDelay`:

```solidity
function _updateGovernorDelay(uint256 newGovernorDelay) internal {
    uint256 minDelay = _timelock.getMinDelay();
    if (newGovernorDelay < minDelay) {
        revert Underflow(newGovernorDelay, minDelay);
    }
    ...
    governorDelay = newGovernorDelay;
}
```

However, `TimelockController` exposes a separate `updateDelay` function that can raise
`minDelay` **independently** of `governorDelay`, via a governance-scheduled self-call.
If a proposal raises `minDelay` above the current `governorDelay` value without
simultaneously raising `governorDelay`, all subsequent calls to `Governor.queue()`
will revert at the timelock's `scheduleBatch` `delay >= minDelay` check.

**Impact: circular dependency that can brick governance.**

1. Proposal A raises `minDelay` to a value greater than `governorDelay`.
2. Proposal A is executed → `minDelay` is now higher.
3. Any subsequent `Governor.queue()` call reverts.
4. To recover, governance must call `Governor.updateGovernorDelay(...)`, which is
   `onlyGovernance` — i.e. it must be scheduled via `Governor.queue()` → which
   reverts. Recovery requires governance to fix itself, but governance is the thing
   that's broken.

Recovery paths outside the normal governance flow:

- The `TimelockController` admin (currently the Timelock itself + GovernorOLAS) can
  directly call `updateDelay` to lower `minDelay` back — but that also requires going
  through `Governor.queue()`, which is broken.
- The CM Safe holds `PROPOSER_ROLE` + `EXECUTOR_ROLE` on the Timelock and can
  therefore schedule + execute a `Timelock.updateDelay(...)` call directly,
  bypassing the Governor entirely (§5.5 of internal audit 19 describes this
  fast-path). This is only possible if `Timelock.updateDelay` is in the
  `GuardCM.mapAllowedTargetSelectorChainIds` allowlist. It is the intended
  out-of-band recovery path.

**Why this is not fixed.** The risk is explicitly documented in the contract's natspec:

```solidity
/// CAUTION: It is not recommended to change the timelock while there are other
///          queued governance proposals.
/// CAUTION: minDelay is able to be updated separately, thus it is highly recommended
///          to change governanceDelay simultaneously in order for it to never be
///          smaller than minDelay.
```

Enforcing the constraint atomically in code would require `TimelockController`
upgrades (which Olas doesn't use — contracts are deployed directly, not behind
proxies) or a more invasive wrapper around `updateDelay`. The documented
discipline — always update both in the same proposal — is the accepted mitigation.

**Mitigation / guidance for governance operators.**

1. **Always update `minDelay` and `governorDelay` in the same governance proposal.**
   Any proposal that calls `Timelock.updateDelay(newMinDelay)` should, in the same
   batch, also call `Governor.updateGovernorDelay(newGovernorDelay)` with
   `newGovernorDelay >= newMinDelay`.
2. **Prefer to only ever raise both together, or lower `minDelay` first.** Raising
   `minDelay` alone is the specific misstep that bricks queueing.
3. **Keep `Timelock.updateDelay` in the `GuardCM` allowlist** so the CM fast path
   remains available as a break-glass recovery lane if the constraint is violated
   despite the above.

### 14. `VoteWeighting` `addNomineeEVM` and `addNomineeNonEVM` are permissionless

**Severity:** Informative

In the `VoteWeighting` contract, the following two functions are externally callable by anyone, with no access control:

```solidity
function addNomineeEVM(address account, uint256 chainId) external
function addNomineeNonEVM(bytes32 account, uint256 chainId) external
```

This differs from the upstream Curve `GaugeController.add_gauge` design, which is admin-only. In Olas the asymmetry is intentional: anyone can register a nominee (a service / agent / target on some chain), while only `veOLAS` holders can direct emissions via `voteForNomineeWeights`, and only the contract `owner` (the Timelock) can remove nominees via `removeNominee`.

**Impact / griefing surface.**

- **Unbounded array growth.** Each successful add appends to the `setNominees` array. The array only ever shrinks via owner-driven `removeNominee`. An attacker can register an arbitrary number of distinct nominees (each `(account, chainId)` pair must be unique, but the attacker can vary either field freely), inflating `setNominees.length` and increasing the cost of any iteration over it.
- **`IDispenser.addNominee` side-effects.** Each `addNominee*` call also invokes `IDispenser.addNominee()` if a Dispenser is configured, which may cause state changes in the Dispenser contract (cost paid by the attacker on L1 gas, but persistent on the Dispenser side).
- **Misleading nominees.** An attacker can register nominees with names / chain-ids designed to confuse front-end users into voting for the wrong target. The attacker does not gain emissions directly (those still require `veOLAS` voters to allocate weight), but social-engineering attacks on the voter UI become easier.

The practical economic impact is bounded: emissions still require veOLAS voting power, and the asymmetric add-vs-remove cost favours the defender (each spam entry costs the attacker L1 gas; the owner can batch-remove). However, a passive accumulation of spam over months / years would impose a real ops burden.

**Why this is not fixed.** Permissionless add is a deliberate design choice — gating it behind owner-only would add a governance step to every legitimate new nominee, which would slow down the operational cadence of the protocol. The trade-off is "open and slightly griefable" vs. "gated and slow". The Olas design picks the former.

**Mitigation / guidance for operators.**

1. **Off-chain spam filter on the voter UI.** Front-ends that surface the nominee list should filter / rank entries (e.g., by whether the nominee has received any non-attacker votes, or by `(account, chainId)` allowlist), so spam nominees are not equally visible alongside legitimate ones.
2. **Off-chain monitoring of `AddNomineeHash` event volume.** Set an alert on unusual rate of nominee additions. A sudden burst is the cheap signal of a griefing campaign and triggers the cleanup path below.
3. **Periodic owner cleanup.** When spam is detected, the owner (Timelock) can `removeNominee` the spam entries. Note that `removeNominee` orphans voting power (entry #8) and has the slope-drift side-effect (entry #8 sub-finding) — the cleanup should be scheduled rather than reactive, and combined with voter cleanup as described in #8.
4. **Optional code-level cap.** If griefing becomes a sustained problem, a future redeploy could add `if (setNominees.length >= MAX_NOMINEES) revert TooManyNominees();` at the top of `_addNominee`. This is not necessary today.

### 15. `ProcessBridgedDataWormhole` hardcoded `TIMELOCK` constant

**Severity:** Informative

In `ProcessBridgedDataWormhole`, the L1 Timelock address that bridge payloads are required to refund to is a compile-time constant:

```solidity
address public constant TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
```

The verifier rejects payloads whose `refundAddress != TIMELOCK` and whose `refundChainId != REFUND_CHAIN_ID` (= `2`, Ethereum mainnet in Wormhole chain-id space). This is the correct fix for the C4A 2026-01 Arbitrum-class refund-redirection issue (see internal audit 19 §4.1) — but it bakes the Timelock address into the bytecode of `ProcessBridgedDataWormhole`.

This is **inconsistent with the Arbitrum verifier** (`ProcessBridgedDataArbitrum`), which receives the L2 Timelock equivalent as a parameter via `GuardCM.mapBridgeMediatorL1BridgeParams[target].bridgeMediatorL2`. The Arbitrum approach is more flexible — replacing the L2 mediator is a governance call to `setBridgeMediatorL1BridgeParams`, no redeploy required. The Wormhole approach traps the L1 Timelock address in immutable code.

**Impact.**

- **Timelock redeployment forces verifier redeployment.** If the Olas L1 Timelock is ever redeployed (governance migration, security incident, role-rotation that requires fresh contract), every `ProcessBridgedDataWormhole` instance must be redeployed and re-wired into `GuardCM.mapBridgeMediatorL1BridgeParams` for every Wormhole-bridged target. Forgetting to redeploy the verifier would silently break Wormhole-bridged governance (every payload would revert at the `refundAddress != TIMELOCK` check).
- **No on-chain mutability.** Unlike the Arbitrum case, there is no governance-side knob to retarget the verifier — the constant is immutable.

**Why this is not fixed.** The hardcoded constant gives compile-time safety: there is no setter to mis-configure, no allowlist row to forget to populate. For the current deployment (one Timelock, no migration on the roadmap), the rigidity is a feature, not a bug. Parameterising it would re-introduce the operational surface that the Arbitrum verifier already has.

**Mitigation / guidance for operators.**

1. **Capture the redeploy-coupling rule in any Timelock-redeploy runbook.** Specifically: "If `Timelock` is redeployed, then every `ProcessBridgedDataWormhole` deployment must also be redeployed at the same time, and `GuardCM.setBridgeMediatorL1BridgeParams` must be re-called for every Wormhole target with the new verifier address."
2. **On the next bridge-verifier redeploy** (the upcoming one bundled with the C4A M-01 fix and the new `GovernorOLAS`, see internal audit 19 §5.4), consider parameterising the L1 Timelock address the same way the Arbitrum verifier parameterises the L2 mediator. This is a one-time refactor that aligns the two verifier shapes and removes this redeploy-coupling. Not required to land the M-01 fix; can be a follow-up.
3. **Until then**, treat the Wormhole verifier address as a satellite of the Timelock address — they move together or not at all.

### 16. `GuardCM` `setTargetSelectorChainIds` does not bound `chainId`

**Severity:** Informative

In the `GuardCM` contract, the following function is implemented:

```solidity
function setTargetSelectorChainIds(
    address[] memory targets,
    bytes4[] memory selectors,
    uint256[] memory chainIds,
    bool[] memory statuses
) external
```

The allowlist key packs `target(160) | selector(32) | chainId(64)` into a single `uint256` via `chainId << 192`. Only `chainId != 0` is validated; the sibling setter `setBridgeMediatorL1BridgeParams` additionally enforces `chainId <= MAX_CHAIN_ID`, but this one does not.

**Impact.** A `chainId >= 2^64` shifts its high bits out of the 256-bit word, so e.g. `2^64 + 5` packs identically to `5`. An owner authorizing a malformed or oversized `chainId` therefore writes the allow-flag under `(chainId mod 2^64)` — a different combination than intended. The enforcement read (`VerifyData.sol` around line 31) and the bridged path pass an already-bounded `chainId`, so this is an **owner-write configuration-integrity defect only**, not an unprivileged exploit. Discovered in the internal20 manual re-audit.

**Why this is not fixed.** `GuardCM` is not upgradeable. Owner input is trusted (owner is the Timelock), so a mis-entry does not break funds or grant new capabilities to third parties — it only silently mis-keys the allowlist. Fixed on a future redeployment.

**Mitigation / guidance for governance operators.** Any governance proposal calling `GuardCM.setTargetSelectorChainIds` should be reviewed for `chainId <= MAX_CHAIN_ID` on each entry, matching the sibling setter's constraint. Front-ends and calldata annotators that surface such proposals should flag `chainId >= 2^64` as an error before signing.

**Fix on redeploy.** Add `if (chainIds[i] > MAX_CHAIN_ID) revert L2ChainIdNotSupported(chainIds[i]);` at the top of the loop in `setTargetSelectorChainIds`, matching `setBridgeMediatorL1BridgeParams`.

### 17. Cross-chain verifiers do not bound the per-record native `value`

**Severity:** Low

Location: `multisigs/bridge_verifier/VerifyBridgedData.sol` (record-parsing helper skips the per-record 12-byte `value`); L2 executors forward it at `bridges/HomeMediator.sol`, `bridges/FxGovernorTunnel.sol`, `bridges/BridgeMessenger.sol`.

The bridged-payload verifier authorizes `(target, selector, chainId)` per record but skips the 12-byte per-record native `value`. The L2 executors then forward that value via `target.call{value: value}(payload)`, bounded only by the mediator's own native balance.

**Impact.** A guard-authorized `(target, selector, chainId)` triple says nothing about the native value the L2 mediator will spend on it. A scheduled record can carry an arbitrary `value` (up to the mediator's balance) into an allowlisted target that the L1 authorizer never saw. The trigger is the threshold-trusted Community Multisig (not unprivileged); the destination must still be an allowlisted target; the amount is capped by the mediator's balance (typically ~0 for a pure relay). But the L1 authorizer should constrain what the L2 executor spends. This is a **cross-chain robustness defect**, not a fund-loss exploit on today's mediator balances. Discovered in the internal20 manual re-audit.

Distinct from the top-level `value` checks already present on the Arbitrum / Wormhole verifiers (`l2CallValue == 0` / `receiverValue == 0`): those constrain the outer envelope; this one is the **inner per-record `value`** inside the bridged batch.

**Why this is not fixed.** The verifier contracts are not upgradeable. Live L2 mediators do not hold native balance that could underwrite an unintended spend, so the defect is bounded on the deployment as it stands. Fixed on a future redeployment of the verifiers.

**Mitigation / guidance for operators.**

1. **Do not fund the L2 mediators** (`HomeMediator`, `FxGovernorTunnel`, `BridgeMessenger`) with native tokens above operational-relay needs. The exposure ceiling equals the mediator's balance.
2. **Off-chain calldata review** of any CM-scheduled bridged batch should inspect the per-record `value` field even though the on-chain verifier does not. Any non-zero per-record `value` on a non-payable target selector is a red flag.

**Fix on redeploy.** In `_verifyBridgedData`, read the 12-byte per-record `value` and require it to be `0` for non-payable allowlisted selectors (mirror the Arbitrum verifier's `l2CallValue == 0` check), or add a per-target `value` bound.

### 18. `VoteWeighting` `_nomineeRelativeWeight` not capped at `1e18`

**Severity:** Low

In the `VoteWeighting` contract, the following internal function is implemented (docstrings around lines 414 and 437 promise "not more than 1.0"):

```solidity
function _nomineeRelativeWeight(bytes32 account, uint256 chainId, uint256 time)
    internal view returns (uint256 weight, uint256 totalSum)
{
    // ...
    weight = 1e18 * nomineeWeight / totalSum;
    // no clamp
}
```

The function's own docstring promises `weight <= 1e18`. When `totalSum` under-counts relative to a surviving nominee's `nomineeWeight` — which can happen via the removal-accounting drift documented in entry #8 — the result exceeds `1e18`, violating the contract's own stated invariant.

**Impact — cross-contract seam.** This view is consumed by the off-repo incentive distributor (`Dispenser`) to split staking incentives across nominees. A returned value `> 1e18` at the Dispenser leads to **over-allocation** of staking incentives to that nominee vs. the design (each nominee should receive at most 100 % of the epoch pot). The trigger condition is the removal-accounting drift, so the exposure follows the same feasibility profile as entry #8 (owner-scoped rare action + passive-voter follow-through). Discovered in the internal20 manual re-audit.

**Status — addressed in the pending VoteWeighting redeployment.** `VoteWeighting` is not upgradeable, so this is fixed by redeploying the contract; the clamp described below is implemented and takes effect once the new VoteWeighting is deployed and adopted via governance. Until then, the same voter-cleanup discipline that mitigates entry #8 (voter revoke / vote-zeroing before each `removeNominee`) also prevents the `totalSum` drift that would take `_nomineeRelativeWeight` above `1e18`.

**Mitigation / guidance for the Dispenser integrator.** The staking-incentive distributor should treat `_nomineeRelativeWeight` as a value in `[0, 1e18]` and clamp defensively on its side (`if (w > 1e18) w = 1e18;`) before using it as a fractional multiplier. This is defence in depth against the same accounting-drift condition that mitigates #8 operationally.

**Fix on redeploy.** Clamp at the return site: `if (weight > 1e18) weight = 1e18;`. Independent of the deeper entry #8 accounting fix — the clamp is defence in depth for the Dispenser consumer.

### 19. `VoteWeighting` `removeNominee` last-element guard mismatch

**Severity:** Informative

In the `VoteWeighting` contract, `removeNominee` performs a swap-and-pop over `setNominees`. The intent — stated by the code comment at approximately line 623 — is to skip the swap when removing the last element of the array. The guard implementing that intent uses `if (numNominees > 1)` when it should use `if (id != numNominees)`.

Removing the **last** of ≥ 2 nominees still enters the swap-and-pop branch (`numNominees > 1` is true). Traced on `[sentinel, A, B]` removing `B (id = 2)`:

- line 627 re-reads `setNominees[2] = B`;
- line 628 recomputes `hash(B)`;
- line 629 sets `mapNomineeIds[hash(B)] = 2` — **re-writing the value that line 620 had correctly zeroed**;
- line 633 pops the array.

Post-state: the removed nominee is present in both `mapRemovedNominees` (≠ 0) and `mapNomineeIds` (= its old id, now dangling past the array end).

**Impact — view-only.** `getNomineeId` / `getNextAllowedVotingTimes` (which key existence off `mapNomineeIds == 0`) return stale data to off-chain consumers. Every on-chain value-bearing path is independently guarded by `mapRemovedNominees` (re-add blocked at line 301, voting blocked at line 479, `getNominee(staleId)` reverts on the length bound at line 766), so the dangling entry **cannot be chained into a fund/vote effect**. The on-chain state is genuinely wrong; the downstream guardrails prevent any exploitable consequence. Discovered in the internal20 manual re-audit.

**Status — addressed in the pending VoteWeighting redeployment.** `VoteWeighting` is not upgradeable, so this is fixed by redeploying the contract; the guard change described below is implemented and takes effect once the new VoteWeighting is deployed and adopted via governance.

**Mitigation / guidance for tooling.** Off-chain consumers reading `mapNomineeIds` should additionally check `mapRemovedNominees` before treating a returned id as active — matching the on-chain guard set that already gates any value-bearing effect.

**Fix on redeploy.** Change the guard to `if (id != numNominees)` so removing the last element skips the swap-write branch and does not re-populate `mapNomineeIds` for the just-removed nominee.

### 20. `VoteWeighting` `revokeRemovedNomineeVotingPower` missing checkpoint advance

**Severity:** Informative

In the `VoteWeighting` contract, `revokeRemovedNomineeVotingPower` (around lines 666–668) writes `pointsSum` / `pointsWeight` slope via `_maxAndSub` **without first calling** `_getSum()` / `_getWeight()` to advance the slot to `nextTime`. The peer function `voteForNomineeWeights` correctly performs those advances at lines 533–534.

**Impact.** If `revokeRemovedNomineeVotingPower` runs in a week later than the last checkpoint, the target `nextTime` slot is stale (0), so `_maxAndSub(0, oldSlope.slope)` floors to `0` and the voter's slope removal is silently lost — while `changesSum[oldSlope.end] -= oldSlope.slope` (around line 674) still executes. A residual slope then over-decays the sum until natural expiry. (Line 674 itself cannot underflow: the voter's own contribution is present and guarded by `oldSlope.end > block.timestamp`.) The net effect is **gauge-weight accounting drift — no funds, no DoS, self-converging** once the phantom slope decays. Compounds the same class of accounting seam that entry #8 describes. Discovered in the internal20 manual re-audit.

**Status — addressed in the pending VoteWeighting redeployment.** `VoteWeighting` is not upgradeable, so this is fixed by redeploying the contract; the fix described below is implemented and takes effect once the new VoteWeighting is deployed and adopted via governance. The shipped design differs from the original recommendation: rather than advancing the checkpoint inside revoke, the redeployed `removeNominee` fully reconciles the aggregate, which removes the stale-slot condition by construction (see **Fix on redeploy** below).

**Mitigation / guidance for voters.** A voter intending to revoke should either:

1. Call `revokeRemovedNomineeVotingPower` in the same week as the removal, before the checkpoint slot goes stale; or
2. First force a checkpoint advance to `nextTime` by calling a state-writing function on `VoteWeighting` that runs `_getSum()` / `_getWeight()` in the same transaction context (e.g., voting on an existing active nominee), before invoking the revoke.

**Fix on redeploy (as shipped).** The redeployed `removeNominee` fully reconciles the aggregate for a removed nominee — bias, still-active slope, and its future `changesSum` entries — inside the removal itself. `revokeRemovedNomineeVotingPower` is therefore reduced to pure per-user bookkeeping (release the caller's `voteUserSlopes` / `voteUserPower` and emit the event) and deliberately does **not** touch `pointsSum` / `pointsWeight` / `changesSum` / `changesWeight` again. Because the aggregate is already settled at removal time, there is no stale next-week checkpoint slot left to advance — so the missing `_getSum()` / `_getWeight()` advance is resolved **by construction**, not by mirroring `voteForNomineeWeights` (which here would double-subtract the removed nominee's slope).

### 21. `GuardCM` `mapBridgeMediatorL1BridgeParams` keyed by L1 address only

**Severity:** Informative

Location: `multisigs/GuardCM.sol` (`mapBridgeMediatorL1BridgeParams` around line 134, setter around line 394); `BridgeParams` struct around line 42 carries `chainId`, but the mapping key does not.

`GuardCM.mapBridgeMediatorL1BridgeParams` is keyed by the L1 mediator address only, although the `BridgeParams` value struct carries `chainId`. **A bridge family that uses one L1 entry point for multiple destination chains would collide** — the second `setBridgeMediatorL1BridgeParams` call overwrites the first.

This is intended under the documented "each L2 verifier has a unique association with the L1 bridge mediator" design, which holds for the four live verifiers today (Arbitrum / Gnosis / Optimism-stack / Polygon — each has a distinct L1 mediator address). The only family that violates the premise is a single-relayer model where one L1 entry point routes to multiple L2s. Discovered in the internal20 manual re-audit.

**Dormancy status (verified on-chain).** The live `GuardCM` has no bridge entry configured that would share an L1 mediator across chains. No live path can trigger the collision.

**Why this is not fixed.** `GuardCM` is not upgradeable; the mapping shape is fixed. Corrected on a future redeployment.

**Mitigation / guidance for governance operators.** Hold the invariant "never configure two `mapBridgeMediatorL1BridgeParams` entries that share one L1 mediator address" on any future allowlist change. Any bridge family under consideration that violates the premise (a shared single-relayer routing multiple L2s) must be rejected at the allowlist-review stage until the mapping shape is fixed.

**Fix on redeploy.** On any reintroduction of a shared-L1-relayer bridge family, change the mapping to a composite `(L1, chainId)` key before wiring the two conflicting entries. Update `setBridgeMediatorL1BridgeParams` and all reads accordingly.

### 22. `WormholeMessenger` single `sourceGovernor` authentication

**Severity:** Informative

Location: `bridges/WormholeMessenger.sol` (single `sourceGovernor` state variable; authentication around lines 88–95).

`WormholeMessenger` authenticates against a single `sourceGovernor`, which cannot match two distinct L1 sender identities (a direct path and a mediated path) simultaneously. Correspondingly the matching verifier accepts only the direct-relayer signatures. Discovered in the internal20 manual re-audit.

**Dormancy status.** Only the single direct path is (was) live, and that bridge family is being retired. No live path exercises the dual-source case.

**Why this is not fixed.** `WormholeMessenger` is not upgradeable, and the bridge family is being retired. The single-source authentication is correct as long as governance uses only one L1 sender identity for this bridge.

**Mitigation / guidance for governance operators.** If dual-path governance over the Wormhole bridge is ever reintroduced, the receiver / verifier must accept the **set** of legitimate source authorities rather than one. Until then, all cross-chain governance messages over Wormhole must originate from the currently configured `sourceGovernor` only.

**Fix on redeploy.** If dual-path Wormhole governance is reintroduced, extend `sourceGovernor` to a set / mapping keyed on the sender identity, and update the verifier accordingly.

### 23. `Timelock` deployer-EOA admin bootstrap window

**Severity:** Informative

Location: `Timelock.sol` (constructor, passing `msg.sender` as the OZ v4.8 `TimelockController` 4th "admin" argument).

`TimelockController`'s constructor grants `TIMELOCK_ADMIN_ROLE` to the deploying account passed as the 4th constructor arg (`msg.sender` for the Olas wrapper) — a delay-bypassing role during the bootstrap window until the deployer renounces it. Discovered in the internal20 manual re-audit.

**Dormancy status (verified on-chain).** The live deployment renounced the deployer-EOA admin. `Timelock` is now self-administered (`hasRole(TIMELOCK_ADMIN_ROLE, self) == true`, deployer holds `false`). The bootstrap window is closed on the live contract.

**Why this is not fixed.** `Timelock` is deployed and not upgradeable; the window has already closed on the live contract. The bootstrap-role model is inherent to the OZ v4.8 admin pattern.

**Mitigation / guidance for redeployment operators.** Any future `Timelock` redeploy operator should renounce the deployer-EOA admin as the very first post-deploy transaction (no gap between deploy and renounce). The dormancy on the current deployment does not carry over to a future redeploy — the window reopens at every fresh deploy.

**Fix on redeploy.** Pass `address(0)` as the 4th ctor arg to fully remove the bootstrap window, and grant `TIMELOCK_ADMIN_ROLE` to the intended admin (e.g., the Timelock itself) via a separate post-deploy call under a bootstrap key. This removes the deployer-EOA bootstrap window entirely.

### 24. `FxERC20RootTunnel` `setFxChildTunnel` is a permissionless one-shot

**Severity:** Informative

Location: `FxERC20RootTunnel` inherits from `fx-portal`'s `FxBaseRootTunnel`, which exposes `setFxChildTunnel(address)` — permissionless, callable exactly once.

`FxBaseRootTunnel.setFxChildTunnel` is permissionless: whoever calls it first pins the L2 emitter for the token bridge. A front-run before the deployer would pin the L2 emitter to an attacker contract, enabling **mint-without-lock on L1** for the bridged token. Discovered in the internal20 manual re-audit.

**Dormancy status.** The window is deploy-time only; the live `FxERC20RootTunnel` already has its child tunnel set. Any subsequent call reverts (the base contract enforces the one-shot). The window is closed on the live contract.

**Why this is not fixed.** The tunnel is deployed and inherits from `fx-portal`'s base; overriding `setFxChildTunnel` would need a redeploy of the tunnel.

**Mitigation / guidance for redeployment operators.** Any future `FxERC20RootTunnel` redeploy must call `setFxChildTunnel` in the same transaction as (or immediately after) deployment — atomically wrapped in a deployer script — to close the front-run window. The dormancy on the current deployment does not carry over.

**Fix on redeploy.** Override `setFxChildTunnel` with `onlyOwner`, or set it in the constructor along with the L1 checkpoint manager / state sender addresses. Either removes the front-run window entirely.

### 25. Unbounded Governor settings and unchecked Timelock replacement can permanently brick governance

**Severity:** Medium

Location: `GovernorOLAS` (via `GovernorSettings` and `GovernorTimelockControl`), functions `setProposalThreshold`, `setVotingDelay`, `setVotingPeriod`, `updateGovernorDelay`, and `updateTimelock`.

The Governor exposes several configuration setters that accept an unbounded value (or, for the Timelock, an unvalidated replacement), and each is powerful enough that a single unsafe value can leave governance permanently unable to operate:

- **`setProposalThreshold`** — set arbitrarily high, no proposer can ever meet the threshold, so `propose()` can no longer be called and proposal creation is permanently disabled.
- **`setVotingDelay`** (and `setVotingPeriod`) — set to an extreme value, the voting schedule for any new proposal is pushed out indefinitely, so proposal creation / voting is effectively disabled.
- **`updateGovernorDelay`** — set to an extreme value, a queued proposal's execution ETA becomes
  unreachable, so nothing can ever be executed and governance is frozen. Note this setter is **not**
  fully unbounded: `_updateGovernorDelay` already rejects a value below the timelock's `minDelay`
  (`revert Underflow(newGovernorDelay, minDelay)`). Only the **upper** direction is unconstrained.
  That existing floor is *relative* — it tracks `timelock.getMinDelay()`, which is itself separately
  updatable, which is the coupling item 13 describes.
- **`updateTimelock`** — replace the referenced Timelock with one that does not have the proposer /
  executor / canceller roles wired to the Governor. The replacement is validated against **nothing**:
  `_updateTimelock` emits and assigns, with no role check and **no zero-address check**, so
  `updateTimelock(TimelockController(address(0)))` is accepted. A zero Timelock is a worse end state
  than one that is merely unwired, because every subsequent queue / execute path then calls into a
  codeless address.

**Why this is not externally exploitable.** All four setters are `onlyGovernance` — the modifier requires the caller to be the Governor's executor (the Timelock). None is reachable by an arbitrary external account; a direct call reverts. Each can only take effect as the *result of a proposal that has cleared the proposal threshold, quorum and majority vote, waited out the timelock delay, and executed*. There is no value transfer or extraction in any of the four — the only effect is denial of governance, so there is no profit motive: an actor with enough voting power to force one of these through would gain nothing from a self-brick that they could not gain more directly. The realistic path to this state is therefore **operator error** — a legitimate proposal that sets one of these parameters to an unsafe value — rather than an attack.

**Mitigation / guidance for governance operators.** Treat these parameters as safety-critical when composing any proposal: keep `proposalThreshold`, `votingDelay`, `votingPeriod` and `governorDelay` within sane, pre-agreed bounds, and never queue a value that could make proposing, voting or execution infeasible. When replacing the Timelock, wire the proposer / executor / canceller roles to the Governor on the new Timelock **before** (or atomically with) the replacement, and verify the wiring on a testnet fork first. Keep an independent recovery path available so that, if governance ever reaches a non-operational configuration, it can still be restored.

**Why Medium rather than Informative.** The neighbouring entries with comparable reachability are rated
Informative — including item 24, which is *permissionless*, and item 13, which concerns this same
`governorDelay` / `minDelay` relationship. The distinction here is **recoverability**, not reachability:
item 13's desynchronisation can be corrected by a subsequent proposal, whereas each end state described
above removes the very mechanism (proposing, voting, or executing) needed to correct it. That is what the
Medium records.

**Fix on redeploy.** On a future Governor redeploy:

1. **Bound the settable ranges.** Reject a `proposalThreshold` / `votingDelay` / `votingPeriod` /
   `governorDelay` outside a configured min–max. For `governorDelay`, note that a lower bound already
   exists and is *relative* to `timelock.getMinDelay()`; only a ceiling is missing. A static min–max must
   not replace that relative floor, or it would reintroduce the item-13 desynchronisation it currently
   prevents.
2. **Add a zero-address check to `updateTimelock`.** One line, and it closes the most damaging variant
   (a Governor pointed at a codeless address). Worth landing independently of step 3.
3. **Validate role wiring in `updateTimelock`.** Require that the new Timelock grants the Governor the
   `PROPOSER` / `EXECUTOR` / `CANCELLER` roles before accepting it. This is the larger change; steps 2
   and 3 are separable and should not be blocked on each other.

[^1]: The level of the bug is assigned by following the [Immunefi classification](https://immunefi.com/).
[^2]: Since no manipulation of governance voting can currently happen, this vulnerability identifies a smart contract that fails to deliver promised returns but doesn't lose value.
[^3]: This function is not currently used in any of the Autonolas on-chain contracts, thus this vulnerability identifies a smart contract that fails to deliver promised returns but doesn't lose value.
[^4]: When voting via veOLAS, the incorrect value is returned as a read-only value, thus this could be declared as a Low severity. However, if there are consequences due to incorrect voting failure, then it is a potential damage to the DAO members, and then the severity is Medium.

### 26. `VoteWeighting` catch-up cursors do not advance across a multi-year gap

**Severity:** Informative

`_getSum()` walks at most `MAX_NUM_WEEKS = 250` weeks per call and persists its cursor **only** when it
reaches a week beyond the present:

```solidity
uint256 t = timeSum;
for (uint256 i = 0; i < MAX_NUM_WEEKS; i++) {
    if (t > block.timestamp) break;
    t += WEEK;
    ...
    pointsSum[t] = pt;
    if (t > block.timestamp) {
        timeSum = t;          // the only write
    }
}
```

If `timeSum` is more than 250 weeks behind `block.timestamp`, the loop exhausts all 250 iterations without
`t` ever passing the present, so `timeSum` is never written. The next call re-reads the same stale cursor
and replays the same window: each call performs work, none of it advances the cursor, and the contract stays
pinned. `_getWeight()` has the same shape for the per-nominee `timeWeight`.

Once pinned, the aggregate is stale for every consumer that reads it. The consequences compound rather than
stand alone — a stalled aggregate slot can be overwritten and re-read, relative weights derived from it
over-allocate against a stale total, and a dormant nominee cursor can be advanced by a permissionless
zero-value vote. All of these follow from the cursor, not from separate defects.

**The precondition is what sets the severity, and the constant documents it as an assumption:**

```solidity
// The number corresponds to more than four years timeframe
// It is enough to have at least one vote while veOLAS value is greater than zero
// In practice it is unlikely that there is no single checkpoint for the maximum amount of weeks
```

250 weeks is roughly **4.8 years**. Reaching the stuck state requires no checkpoint of any kind for that
entire period. Checkpointing is permissionless and is driven by ordinary reward claims, so the gap implies a
protocol with no claims and no votes for nearly five years. The consequences are severe; the entry condition
is a dormant protocol.

**Related.** Item 8 documents a *different* defect in the same function — a permanent checkpoint DoS from
phantom slopes left by expired locks. That one reverts the walk; this one completes the walk without
advancing. They are independent, and a fix for either does not address the other.

**Mitigation.** Persist the cursor unconditionally at the end of the walk rather than only on reaching a
future week, so that a long gap is closed incrementally across successive calls instead of being replayed.
Operationally, any checkpoint activity at all — a vote, a reward claim, a manual `checkpoint()` — keeps the
cursor current and prevents the state from being reachable.

### 27. Nominees can be added for chains that cannot receive incentives

**Severity**: Low
**Source**: internal review

`VoteWeighting.addNomineeEVM` validates the shape of a chain id but not whether that chain can actually be
paid:

```solidity
if (account == address(0)) { revert ZeroAddress(); }
if (chainId == 0) { revert ZeroValue(); }
if (chainId > MAX_EVM_CHAIN_ID) { revert Overflow(chainId, MAX_EVM_CHAIN_ID); }
```

There is no check against the deposit-processor map the incentive path relies on. Registration is
permissionless, so a nominee can be added for a chain with no configured processor and voted into
`pointsSum` like any other. When a claim is later attempted for it, the incentive path dereferences the
zero processor and reverts.

**The revert happens on L1, before anything is dispatched, in a call whose targets the caller supplies** —
so the caller simply omits that nominee and claims the rest. Nothing is denied to anyone else and no funds
move. What remains is that weight directed at such a nominee is unclaimable and dilutes the nominees that
can be paid, which costs the voter their own voting power to arrange. Rejecting unsupported chain ids at
registration closes it at the cheapest point.

At the time of writing every live nominee is on a chain with a configured processor.
