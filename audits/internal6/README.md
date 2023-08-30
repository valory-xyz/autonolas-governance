# autonolas-governance-audit
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-governance` <br>
commit: `27519122101f85060902b1d309f45072c29e4119` or `v1.1.6-pre-internal-audi` <br> 

Update: 30-08-2023  <br>

## Objectives
The audit focused on Guard contract for community mutisig. <BR>

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal6/analysis/contracts)

### Coverage
Hardhat coverage has been performed before the audit and can be found here:
```sh
------------------------|----------|----------|----------|----------|----------------|
File                    |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
------------------------|----------|----------|----------|----------|----------------
 contracts/multisigs/   |      100 |      100 |      100 |      100 |                |
  GuardCM.sol           |      100 |      100 |      100 |      100 |                |
------------------------|----------|----------|----------|----------|----------------|
```

### Storage timelock
Using sol2uml tools: https://github.com/naddison36/sol2uml <br>
```bash
sol2uml storage . -f png -c GuardCM -o .
Generated png file GuardCM.png
```
Storage: [GuardCM](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal6/analysis/GuardCM.png)

### Security issues
Details in [slither_full](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal6/analysis/slither_full.txt) <br>
Minor issue: <br>
- lacks a zero-check on constructor
[x] fixed - same as in other contracts, no need for the sanity check as we deploy on test networks as well

Notes: <br>
- You need to add it in some initializer (for example, in the constructor) pre-defined list of mapAllowedTargetSelectors.
[x] fixed - decided to not create pre-defined targets and selectors

- Please, add the following tests: 
-- CM owners can't call addOwnerWithThreshold() after installing Guard.
[x] fixed - there is a test that tries to call the getThreshold() function on self multisig.
-- In "Guarded CM can still do other actions" transfer ETH from CM.
[x] fixed - added the test.






 
