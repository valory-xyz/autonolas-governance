# autonolas-governance-audit
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-governance` <br>
commit: `35f2b8386cdcfd7659aa06937ec1ba2f92a29bf1` or `tag: v1.2.4-pre-internal-audit` <br> 

Update: 12-06-2025  <br>

## Objectives
The audit focused on WormholeRelayerTimelock. <BR>

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal14/analysis/contracts)

### Coverage
Hardhat coverage has been performed before the audit and can be found here:
```sh
  WormholeRelayerTimelock.sol         |        0 |        0 |        0 |        0 |... 162,166,169 |
```
Please, pay attention and add tests.
[]


### Security issues
Details in [slither_full](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal14/analysis/slither_full.txt) <br>
All is false positive.

Notes: <br>
- Confused refundChainAddress and refundValueAddress?
```
Two refund addresses are not an bug, but they can be confusing (IMO). 
What about returning everything to one address in L1?
But this is not a bug.
```
[]

Low issue/Notes: <br>
- ZeroAddress check in `constructor`
```
But this is not a bug. Checked by deployment process.
```
[] 

