# autonolas-governance-audit
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-governance` <br>
commit: `7d695d2f3a39cba2fcd655bea3ca703521233872` or `v1.1.3-pre-internal-audit` <br> 

Update: 15-05-2023  <br>

## Objectives
The audit focused on `HomeMediator` contract.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal4/analysis/contracts)

### Coverage
Hardhat coverage has been performed before the audit and can be found here:
```sh
-------------------------|----------|----------|----------|----------|----------------|
File                     |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-------------------------|----------|----------|----------|----------|----------------|
  HomeMediator.sol       |      100 |      100 |      100 |      100 |                |
```

### Security issues (instumantal)
Some of the checks are obtained automatically. They are commented and I do not see any serious problems.

All automatic warnings are listed in the following file, concerns of which we address in more detail below:
[slither-full](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal4/analysis/slither_full.txt)
No issue.

Notes: <br>
Reentrancy in HomeMediator.processMessageFromForeign does not seem feasible.

### Needed Improvements
Low priority.
```
Rename 
AMBMediator AMB Mediator address (Gnosis)
to
"AMB Contract Proxy (Home)"	0x99Ca51a3534785ED619f46A79C7Ad65Fa8d85e7a (in table "Contract - Address")
or
"Home Bridge contract" (in pic https://docs.gnosischain.com/assets/images/amb-bridge-contract-flow-5c9e306d71f1f6513874f0062cf3b673.png)
ref: https://docs.gnosischain.com/bridges/tokenbridge/amb-bridge
IForeignMediator doesn't look like a very good name (sounds like an interface to "ForeignMediator" contract).
```
[x] fixed.



 
