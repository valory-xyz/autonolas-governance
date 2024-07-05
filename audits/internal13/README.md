# autonolas-governance-audit
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-governance` <br>
commit: `59aa1c8732397c826bb67fc567b81b8d0cd82b00` or `tag: v1.2.2-pre-internal-audi` <br> 

Update: 05-07-2024  <br>

## Objectives
The audit focused on fixing VoteWeighting after C4A external audit. <BR>

### Coverage
Hardhat coverage has been performed before the audit and can be found here:
```sh
--------------------------------------|----------|----------|----------|----------|----------------|
File                                  |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
--------------------------------------|----------|----------|----------|----------|----------------|
  VoteWeighting.sol                   |      100 |    98.94 |      100 |    99.56 |            484 |

        int128 userSlope = IVEOLAS(ve).getLastUserPoint(msg.sender).slope;
        if (userSlope < 0) {
            revert NegativeSlope(msg.sender, userSlope);
        }
The fact that this case is not covered is not a problem, since it is very difficult to create such conditions in a real test.
```
#### Checking the corrections made after C4A
64. Less active nominees can be left without rewards after an year of inactivity #64
https://github.com/code-423n4/2024-05-olas-findings/issues/64 <br>
[x] fixed

36. pointsSum.slope Not Updated After Nominee Removal and Votes Revocation #36
https://github.com/code-423n4/2024-05-olas-findings/issues/36 <br>
[x] fixed

16. Incorrect Handling of Last Nominee Removal in removeNominee Function #16
https://github.com/code-423n4/2024-05-olas-findings/issues/16 <br>
[x] fixed

#### Low issue
QA Report #109
https://github.com/code-423n4/2024-05-olas-findings/issues/109
```
Lack of event emission for important state changes in revokeRemovedNomineeVotingPower()
```

