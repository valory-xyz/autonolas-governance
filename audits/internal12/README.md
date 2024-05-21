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

#### Issue
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
[x] fixed

#### Minor issue
CEI pattern: <br>
```sh
Not CEI pattern. Move to end.
        // Remove nominee in dispenser, if applicable
        address localDispenser = dispenser;
        if (localDispenser != address(0)) {
            IDispenser(localDispenser).removeNominee(nomineeHash);
        }

```
[x] fixed

Lacks a zero-check on: <br>
```sh
function changeDispenser(address newDispenser) external {}
```
[x] as designed

No events: <br>
```sh
function changeDispenser(address newDispenser) external {}
function checkpoint() ?
function checkpointNominee() ?
function nomineeRelativeWeightWrite() ?
```
[x] fixed

Naming test issue: <br>
```sh
Rename test\VoteWeighting.js
describe("Voting Escrow OLAS", function () {
```
[x] fixed

README issue: <br>
```sh
No link to https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/GaugeController.vy
```
[x] fixed

Pay attention: <br>
```
https://github.com/trailofbits/publications/blob/master/reviews/CurveDAO.pdf -> 18. Several loops are not executable due to gaslimitation
Discussion: I don't think this is a problem for our version.
```
[x] noted, will check in tests

Version solidity: <br>
```sh
For contracts that are planned to be deployed in mainnet, it is necessary to use the features of the latest hard fork.
https://soliditylang.org/blog/2024/03/14/solidity-0.8.25-release-announcement/
```
[x] fixed

#### Notes
Notes for UX/UI:
```sh
    // Remove the nominee
    await vw.removeNominee(nominees[0], chainId);
    // Get the removed nominee Id
    id = await vw.getNomineeId(nominees[0], chainId);
    expect(id).to.equal(0);
    // Get the id for the second nominee that was shifted from 2 to 1
    id = await vw.getNomineeId(nominees[1], chainId);
            +
    function getNomineeId(bytes32 account, uint256 chainId) external view returns (uint256 id) {
        // Get the nominee struct and hash
        Nominee memory nominee = Nominee(account, chainId);
        bytes32 nomineeHash = keccak256(abi.encode(nominee));

        id = mapNomineeIds[nomineeHash];
    }
    function getNominee(uint256 id) external view returns (Nominee memory nominee) {
        // Get the total number of nominees in the contract
        uint256 totalNumNominees = setNominees.length - 1;
        // Check for the zero id or the overflow
        if (id == 0) {
            revert ZeroValue();
        } else if (id > totalNumNominees) {
            revert Overflow(id, totalNumNominees);
        }

        nominee = setNominees[id];
    }
Due to operation removeNominee(), you must keep in mind that for the same `id` there can be DIFFERENT(!) `nominee` in different time. ref: tests
Does the developer need to add clarification in comments to the source code? 
```
[x] added a comment

General notes (from Curve Finance audit): <br>
```sh
https://github.com/trailofbits/publications/blob/master/reviews/CurveDAO.pdf
4. GaugeController allowsfor quick vote andwithdrawvoting strategy: ref: source variable WEIGHT_VOTE_DELAY
18. Several loops are not executable due to gaslimitation
```
[x] noted and added as a comment

# re-audit. 21.05.24

# autonolas-governance-audit
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-governance` <br>
commit: `9df1f95ec7e51eacb985aece56654b8d2506e29f` or `tag: v1.2.1-pre-internal-audit` <br> 

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal12/analysis2/contracts)

### Coverage
Hardhat coverage has been performed before the audit and can be found here:
```sh
VoteWeighting.sol                   |      100 |    96.67 |      100 |    98.64 |    485,766,768 |
```

### Security issues
Details in [slither_full](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal12/analysis2/slither_full.txt) <br>
all false positive cases.

### Issue
No new issue.

