# autonolas-governance-audit
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-governance` <br>
commit: `fb15c008344cd6c12ae4fa694ba25b47a6c20d03` or `origin/separate_timelock_governor_delay` <br> 

Update: 08-12-2025  <br>

## Objectives
The audit focused on GovernorOLAS/GovernorTimelockControl. <BR>

### Coverage
Hardhat coverage has been performed before the audit and can be found here:
```sh
GovernorOLAS.sol                    |      100 |      100 |      100 |      100 |                |
GovernorTimelockControl.sol         |    85.71 |    59.09 |    84.62 |    86.49 |... ,92,179,185 |
```
Please, pay attention and add tests.
[] 


### Security issues
#### Notes. Comment on the key change
```
This is the main difference.
Please, comment line:
uint256 delay = governorDelay;
https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.6/contracts/governance/extensions/GovernorTimelockControl.sol#L100
```
[]

#### Notes. A similar comment needs to be added.
```
CAUTION: It is not recommended to change the timelock while there are other queued governance proposals.
=> 
function updateGovernorDelay(uint256 newGovernorDelay)
```
[]

#### Notes. For external audit (no problem)
```
Ref:
https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.6/contracts/governance/extensions/GovernorTimelockControl.sol
The code correctly repeats all the necessary code taken from the corresponding version OZ.
```
[x] Noticed.