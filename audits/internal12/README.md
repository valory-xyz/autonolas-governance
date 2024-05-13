# autonolas-governance-audit
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-governance` <br>
commit: `6c39aa6dcdc0111fd8d70bb4df3433d93d4cae99` or `tag: v1.2.0-internal-audit` <br> 

Update: 13-05-2024  <br>

## Objectives
The audit focused on VoteWeighting. <BR>

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal12/analysis/contracts)


### Coverage
Hardhat coverage has been performed before the audit and can be found here:
```sh
--------------------------------------|----------|----------|----------|----------|----------------|
File                                  |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
--------------------------------------|----------|----------|----------|----------|----------------|
  VoteWeighting.sol                   |      100 |      100 |      100 |      100 |                |
```

### Fuzzing VoteWeighting

#### Prepare contracts for fuzzing
contracts/test/VoteWeightingFuzzing.sol <br>
contracts/test/EchidnaVoteWeightingAssert.sol <br> 

#### Fuzzing
```sh
# Move the script to the root of the project
cp start_echidna.sh ../../../../../../
# Move config file to the root of the project
cp echidna_assert.yaml ../../../../../
cd ../../../../../../
# Run 
./start_echidna.sh
```
result overflow: [fuzzing-overflow.PNG](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal12/analysis/fuzzing/overflow/fuzzing-overflow.PNG) <br>
result assert: [fuzzing-assert.PNG](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal12/analysis/fuzzing/overflow/fuzzing-assert.PNG)


### Security issues
Details in [slither_full](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal12/analysis/slither_full.txt) <br>



