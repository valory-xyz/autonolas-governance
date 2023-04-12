# autonolas-governance-audit
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-governance` <br>
commit: `01c92ed0b79a72ffac35191b2cb91aa46022b1b1` <br> 

Update: 12-04-2023  <br>

## Objectives
The audit focused on `FxGovernorTunnel` contract.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal3/analysis/contracts)

### Coverage
Hardhat coverage has been performed before the audit and can be found here:
```sh
------------------------|----------|----------|----------|----------|----------------|
File                    |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
------------------------|----------|----------|----------|----------|----------------|
 contracts/bridges/     |      100 |      100 |      100 |      100 |                |
  FxGovernorTunnel.sol  |      100 |      100 |      100 |      100 |                |
```

### Security issues (instumantal)
Some of the checks are obtained automatically. They are commented and I do not see any serious problems.

All automatic warnings are listed in the following file, concerns of which we address in more detail below:
[slither-full](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal3/analysis/slither_full.txt)
- zero-check on ```target.call{value: value}(payload);``` . Low risk.
[x] fixed.

Notes: <br>
Reentrancy in FxGovernorTunnel.processMessageFromRoot does not seem feasible.

### Needed Improvements and Bugs fixning
changeRootGovernor not event.
[x] fixed.


 
