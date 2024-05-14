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

Issue: <br>
Bug in viper->solidity conversion.
```sh
convert in viper more safe than solidity
https://vyper.readthedocs.io/_/downloads/en/stable/pdf/
• Converting between signed and unsigned integers reverts if the input is negative.
bug on line:
uint256 slope = uint256(uint128(IVEOLAS(ve).getLastUserPoint(msg.sender).slope));

Proof:
uint256 slope = uint256(uint128(IVEOLAS(ve).getLastUserPoint(msg.sender).slope));
to
// Hack
pp = IVEOLAS(ve).getLastUserPoint(msg.sender).slope;
pp = -10;
uint256 slope = uint256(uint128(pp));
console.log(slope);
console.log("bug: negative getLastUserPoint() is possible");

340282366920938463463374607431768211446
bug: negative getLastUserPoint() is ok
```
Minor issue: <br>
CEI pattern: <br>
```sh
Not CEI pattern. Move to end.
        // Remove nominee in dispenser, if applicable
        address localDispenser = dispenser;
        if (localDispenser != address(0)) {
            IDispenser(localDispenser).removeNominee(nomineeHash);
        }

```
Lacks a zero-check on: <br>
```sh
function changeDispenser(address newDispenser) external {
```
Naming test issue: <br>
```sh
Rename test\VoteWeighting.js
describe("Voting Escrow OLAS", function () {
```
README issue: <br>
```sh
No link to https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/GaugeController.vy
```
Pay attention: <br>
https://github.com/trailofbits/publications/blob/master/reviews/CurveDAO.pdf -> 18. Several loops are not executable due to gaslimitation <br>
Discussion: I don't think this is a problem for our version. <br>

Notes: <br>
```
https://github.com/trailofbits/publications/blob/master/reviews/CurveDAO.pdf
4. GaugeController allowsfor quick vote andwithdrawvoting strategy: ref: WEIGHT_VOTE_DELAY
18. Several loops are not executable due to gaslimitation
```


