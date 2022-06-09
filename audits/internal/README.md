# autonolas-governance-audit
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-governance` <br>
commit: `88630be64fde4b51f0cc1f1c9eeb5f515c5f488c` <br> 

Update: 08-06-2022  <br>
Update: 09-06-2022  <br>

This report takes into account the previous report: <br>
https://github.com/valory-xyz/onchain-protocol-audit/tree/main/audit-token-governance

## Objectives
The audit focused primarily on contracts `token` and `governance`

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal/analysis/contracts)

### ERC20 checks
```
slither-check-erc veOLAS-flatten.sol veOLAS    
# Check veOLAS

## Check functions
[✓] totalSupply() is present
        [✓] totalSupply() -> () (correct return value)
        [✓] totalSupply() is view
[✓] balanceOf(address) is present
        [✓] balanceOf(address) -> () (correct return value)
        [✓] balanceOf(address) is view
[✓] transfer(address,uint256) is present
        [✓] transfer(address,uint256) -> () (correct return value)
        [ ] Must emit be view Transfer(address,address,uint256)
[✓] transferFrom(address,address,uint256) is present
        [✓] transferFrom(address,address,uint256) -> () (correct return value)
        [ ] Must emit be view Transfer(address,address,uint256)
[✓] approve(address,uint256) is present
        [✓] approve(address,uint256) -> () (correct return value)
        [ ] Must emit be view Approval(address,address,uint256)
[✓] allowance(address,address) is present
        [✓] allowance(address,address) -> () (correct return value)
        [✓] allowance(address,address) is view
[✓] name() is present
        [✓] name() -> () (correct return value)
        [✓] name() is view
[✓] symbol() is present
        [✓] symbol() -> () (correct return value)
        [✓] symbol() is view
[✓] decimals() is present
        [✓] decimals() -> () (correct return value)
        [✓] decimals() is view

## Check events
[✓] Transfer(address,address,uint256) is present
        [✓] parameter 0 is indexed
        [✓] parameter 1 is indexed
[✓] Approval(address,address,uint256) is present
        [✓] parameter 0 is indexed
        [✓] parameter 1 is indexed


        [ ] veOLAS is not protected for the ERC20 approval race condition
```

```
slither-check-erc OLAS-flatten.sol OLAS
# Check OLAS

## Check functions
[✓] totalSupply() is present
        [✓] totalSupply() -> () (correct return value)
        [✓] totalSupply() is view
[✓] balanceOf(address) is present
        [✓] balanceOf(address) -> () (correct return value)
        [✓] balanceOf(address) is view
[✓] transfer(address,uint256) is present
        [✓] transfer(address,uint256) -> () (correct return value)
        [✓] Transfer(address,address,uint256) is emitted
[✓] transferFrom(address,address,uint256) is present
        [✓] transferFrom(address,address,uint256) -> () (correct return value)
        [✓] Transfer(address,address,uint256) is emitted
[✓] approve(address,uint256) is present
        [✓] approve(address,uint256) -> () (correct return value)
        [✓] Approval(address,address,uint256) is emitted
[✓] allowance(address,address) is present
        [✓] allowance(address,address) -> () (correct return value)
        [✓] allowance(address,address) is view
[✓] name() is present
        [✓] name() -> () (correct return value)
        [✓] name() is view
[✓] symbol() is present
        [✓] symbol() -> () (correct return value)
        [✓] symbol() is view
[✓] decimals() is present
        [✓] decimals() -> () (correct return value)
        [✓] decimals() is view

## Check events
[✓] Transfer(address,address,uint256) is present
        [✓] parameter 0 is indexed
        [✓] parameter 1 is indexed
[✓] Approval(address,address,uint256) is present
        [✓] parameter 0 is indexed
        [✓] parameter 1 is indexed


        [✓] OLAS has increaseAllowance(address,uint256)
```
```
slither-check-erc buOLAS-flatten.sol buOLAS
# Check buOLAS

## Check functions
[✓] totalSupply() is present
        [✓] totalSupply() -> () (correct return value)
        [✓] totalSupply() is view
[✓] balanceOf(address) is present
        [✓] balanceOf(address) -> () (correct return value)
        [✓] balanceOf(address) is view
[✓] transfer(address,uint256) is present
        [✓] transfer(address,uint256) -> () (correct return value)
        [ ] Must emit be view Transfer(address,address,uint256)
[✓] transferFrom(address,address,uint256) is present
        [✓] transferFrom(address,address,uint256) -> () (correct return value)
        [ ] Must emit be view Transfer(address,address,uint256)
[✓] approve(address,uint256) is present
        [✓] approve(address,uint256) -> () (correct return value)
        [ ] Must emit be view Approval(address,address,uint256)
[✓] allowance(address,address) is present
        [✓] allowance(address,address) -> () (correct return value)
        [✓] allowance(address,address) is view
[✓] name() is present
        [✓] name() -> () (correct return value)
        [✓] name() is view
[✓] symbol() is present
        [✓] symbol() -> () (correct return value)
        [✓] symbol() is view
[✓] decimals() is present
        [✓] decimals() -> () (correct return value)
        [✓] decimals() is view

## Check events
[✓] Transfer(address,address,uint256) is present
        [✓] parameter 0 is indexed
        [✓] parameter 1 is indexed
[✓] Approval(address,address,uint256) is present
        [✓] parameter 0 is indexed
        [✓] parameter 1 is indexed


        [ ] buOLAS is not protected for the ERC20 approval race condition
```

### Fuzzing re-check
[fuzzing](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal/analysis/fuzzing)

### Security issues

Some of the checks are obtained automatically. They are commented and I do not see any serious problems.

All automatic warnings are listed in the following file, concerns of which we address in more detail below:
[slither-full](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal/analysis/slither_full.txt)

### Unresolved issues from the previous audit report. Update 09-06-2022
https://github.com/valory-xyz/onchain-protocol-audit/tree/main/audit-token-governance

#### Needed improvements
Missing tests for OLAS token:
- changeOwner [x] (fixed)
- changeMinter [x] (fixed)
- zeroAddress [x] (fixed)
- decreaseAllowance [x] (fixed)
- increaseAllowance [x] (fixed)
- (optional) We can add a test `transferFrom` with allowed == type(uint256).max. [x] (fixed)

Missing tests for veOLA:
- supportsInterface [x] (fixed)
- if (amount > type(uint96).max) [x] (fixed)
- Pay attention to the result of fuzzing: [pre audit fuzzing](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal/analysis/fuzzing/VotingEscrow). Specifically:
-- Pay attention to getPastVotes(0,0) [x] (fixed by additional testing)
It can be taken into account that there is a contract deploy/start time for OLAS: timeLaunch
veOLA should not allow tx to be made earlier than this time.
-- Pay attention _balanceOfLocked with uPoint.bias < 0. This is not a bug(!), because the code in this case always returns 0, but an interesting case. [x] Does not require a code change

### Issues added in this report. Update 09-06-2022
#### Needed improvements
Missing contract:
- Missing `sale contract` with `claim`. Details in `Token launch mechanism specs` [x] (fixed)

Issue in buOLAS:
```
// Locking step time
uint32 internal constant STEP_TIME = 365 * 86400;
// Maximum number of steps
uint32 internal constant MAX_NUM_STEPS = 10;
```
These constants are still not completely defined. [x] still in discussion

Missing tests for buOLAS contract: 
- changeOwner [x] (fixed)
- if (unlockTime > type(uint32).max) [x] (fixed)
- if (amount > type(uint96).max) [x] (fixed)
- supportsInterface() [x] (fixed)
- integration test with revoke() (all possible combinations of 2 functions: revoke() and withdraw() and times). [x] fixed bugs (!)
- function createLockFor test with a amount (18 decimals) with the `amount` that is not evenly divisible by a numSteps [x] fixed
```
amount = uint256(lockedBalance.amountLocked * releasedSteps / numSteps) 
https://ethereum.stackexchange.com/questions/55701/how-to-do-solidity-percentage-calculation

Accounting for the rounding remainder (given that the token contains 18 decimal places) will most likely cost more (in terms of gas spent by the end user) than the current implementation, 
which makes a more accurate calculation meaningless.
```
- Re-test for 4 step in year, 16 steps max (4 years)? [x] still in discussion

Optional tests for veOLA and buOLAS:
- success = IERC20(token).transferFrom(msg.sender, address(this), amount); emulate success == false (i.e. send token to contract with deny in receive()) [x] fixed
- more complicated case: emulate revert ReentrancyGuard() [x] fixed (became obsolete)

#### Notes for implementation of decreaseAllowance
```
if (spenderAllowance != type(uint256).max) {
            spenderAllowance -= amount;
            allowance[msg.sender][spender] = spenderAllowance;
            emit Approval(msg.sender, spender, spenderAllowance);
        }
No precise standard for the implementation of this function has been found.
Therefore, we can consider equally correct interpretation from Maple (decreaseAllowance should behave like transferFrom), as is done now.
There will also be a correct initial implementation of OZ that does not include this check.
The check can be excluded by giving an appropriate comment. 
``` 


#### GovernorOLAS

With the exception of the contract `GovernorSettings`, it looks like it was created from a standard OZ `wizard`
```
https://docs.openzeppelin.com/contracts/4.x/wizard
Result from wizard:
contract MyGovernor is Governor, GovernorCompatibilityBravo, GovernorVotes, GovernorVotesQuorumFraction, GovernorTimelockControl {
    constructor(IVotes _token, TimelockController _timelock)
        Governor("MyGovernor")
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(4)
        GovernorTimelockControl(_timelock)
    {}
```
c3-linearization
```
surya dependencies Timelock Timelock.sol 
Timelock
  ↖ TimelockController

surya dependencies GovernorOLAS GovernorOLAS.sol 
GovernorOLAS
  ↖ GovernorTimelockControl
  ↖ GovernorVotesQuorumFraction
  ↖ GovernorVotes
  ↖ GovernorCompatibilityBravo
  ↖ GovernorSettings
  ↖ Governor
```
Flatten version above.


 
