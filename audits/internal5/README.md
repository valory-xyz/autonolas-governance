# autonolas-governance-audit
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-governance` <br>
commit: `e4180c3b979c912345bcbd30db37c9d42d371e38` or `v1.1.4-pre-internal-audit` <br> 

Update: 19-06-2023  <br>

## Objectives
The audit focused on GovernorOLAS update with latest OZ version. <BR>
NOTES: This audit is not an audit of the code OppenZeppelin itself. Audit of OZ out of scope<br>
It is considering using the previous Timelock contract (without update) with the new version GovernorOLAS.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal5/analysis/contracts)

### Coverage
Hardhat coverage has been performed before the audit and can be found here:
```sh
|  GovernorOLAS            ·  cancel                     ·     117643  ·     120972  ·     119308  ·            2  ·          -  │
···························|·····························|·············|·············|·············|···············|··············
|  GovernorOLAS            ·  castVote                   ·      98428  ·     116096  ·     107676  ·            6  ·          -  │
···························|·····························|·············|·············|·············|···············|··············
|  GovernorOLAS            ·  execute                    ·     160706  ·     164023  ·     162365  ·            2  ·          -  │
···························|·····························|·············|·············|·············|···············|··············
|  GovernorOLAS            ·  propose                    ·     262997  ·     349638  ·     284077  ·           10  ·          -  │
···························|·····························|·············|·············|·············|···············|··············
|  GovernorOLAS            ·  queue                      ·     128142  ·     134806  ·     132030  ·            6  ·          -  │
|  Timelock                ·  cancel                     ·          -  ·          -  ·      25751  ·            2  ·          -  │
···························|·····························|·············|·············|·············|···············|··············
|  Timelock                ·  grantRole                  ·          -  ·          -  ·      51425  ·           26  ·          -  │
···························|·····························|·············|·············|·············|···············|··············
|  Timelock                ·  renounceRole               ·          -  ·          -  ·      24963  ·            3  ·          -  │
···························|·····························|·············|·············|·············|···············|··············
|  Timelock                ·  schedule                   ·      54827  ·      54839  ·      54833  ·            2  ·          -  │
```

### Storage timelock
Using sol2uml tools: https://github.com/naddison36/sol2uml <br>
```bash
new version (based OZ version (4.9.1))
sol2uml storage . -f png -c Timelock -o ..
Generated png file autonolas-governance/audits/internal5/analysis/Timelock.png
сurrent version (based on  OZ version (4.6) on the date of deployment)
sol2uml storage . -f png -c Timelock -o ../../cur/
Generated png file autonolas-governance/audits/internal5/analysis/cur/Timelock.png
```
Line by line diff: [Timelock-flatten-diff.txt](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal5/analysis/Timelock-flatten-diff.txt)

Conclusion: <br>
- No differences in the `Timelock` code which somehow changes the behavior of its functions. <br>
Except for an extra parameter in the constructor and one `event` that we don't use.
```bash
grep CallSalt Timelock-flatten.sol 
    event CallSalt(bytes32 indexed id, bytes32 salt);
     * Emits {CallSalt} if salt is nonzero, and {CallScheduled}.
            emit CallSalt(id, salt);
     * Emits {CallSalt} if salt is nonzero, and one {CallScheduled} event per transaction in the batch.
            emit CallSalt(id, salt);
grep CallSalt cur/Timelock-cur-flatten.sol 

<         TimelockController(minDelay, proposers, executors, msg.sender)
---
>         TimelockController(minDelay, proposers, executors)

```


### Security issues 
No issue.

Notes: <br>
Timelock should not be redeployed.





 
