# autonolas-governance-audit
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-governance` <br>
commit: `1cff6112099d56dc7709e224d64ea907127f5168` or `origin/v1.2.5-pre-internal-audit` <br> 

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
[x] Fixed 


### Security issues
#### Notes. Comment on the key change
```
This is the main difference.
Please, comment line:
uint256 delay = governorDelay;
https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.8.3/contracts/governance/extensions/GovernorTimelockControl.sol#L100
```
[x] Fixed

#### Notes. A similar comment needs to be added.
```
CAUTION: It is not recommended to change the timelock while there are other queued governance proposals.
=> 
function updateGovernorDelay(uint256 newGovernorDelay)
```
[x] Fixed

#### Notes. For external audit (no problem)
```
Ref:
https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.8.3/contracts/governance/extensions/GovernorTimelockControl.sol
The code correctly repeats all the necessary code taken from the corresponding version OZ.
```
[x] Noticed.