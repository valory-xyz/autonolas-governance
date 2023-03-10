# autonolas-governance-audit
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-governance` <br>
tag: `v1.0.2-pre-internal-audit` <br> 

Update: 09-03-2023  <br>

## Objectives
The audit focused on `wveOLAS` contract.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal2/analysis/contracts)

### ERC20 checks
```
slither-check-erc wveOLAS-flatten.sol wveOLAS
# Check wveOLAS

## Check functions
[✓] totalSupply() is present
        [✓] totalSupply() -> (uint256) (correct return type)
        [✓] totalSupply() is view
[✓] balanceOf(address) is present
        [✓] balanceOf(address) -> (uint256) (correct return type)
        [✓] balanceOf(address) is view
[ ] transfer(address,uint256) is missing 
[ ] transferFrom(address,address,uint256) is missing 
[ ] approve(address,uint256) is missing 
[✓] allowance(address,address) is present
        [✓] allowance(address,address) -> (uint256) (correct return type)
        [✓] allowance(address,address) is view
[ ] name() is missing (optional)
[ ] symbol() is missing (optional)
[ ] decimals() is missing (optional)

## Check events
[ ] Transfer(address,address,uint256) is missing
[ ] Approval(address,address,uint256) is missing
```
[x] (fixed)

### Coverage
Hardhat coverage has been performed before the audit and can be found here:
```
------------------------|----------|----------|----------|----------|----------------|
File                    |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
------------------------|----------|----------|----------|----------|----------------|
 contracts/             |          |          |          |          |                |
  wveOLAS.sol           |      100 |      100 |      100 |      100 |                |
```

### Сompliance with the requirement
```
non-wrap = reverted by default in wveOLAS
wrap = called the original veOLAS from wveOLAS
affected = custom logic at wveOLAS side to fixing original veOLAS
non-affected = just call the original veOLAS
 +  veOLAS (IErrors, IVotes, IERC20, IERC165)
    - [Ext] getLastUserPoint (non-affected, wrap) - OK
    - [Ext] getNumUserPoints (non-affected, wrap) - OK
    - [Ext] getUserPoint (affected/improved?, wrap) - OK 
    - [Ext] checkpoint (non-wrap) - OK
    - [Ext] depositFor (non-wrap) - OK
    - [Ext] createLock (non-wrap) - OK
    - [Ext] createLockFor (non-wrap) - OK
    - [Ext] increaseAmount (non-wrap) - OK
    - [Ext] increaseUnlockTime (non-wrap) - OK
    - [Ext] withdraw (non-wrap) - OK
    - [Pub] balanceOf (non-affected, wrap) - OK
    - [Ext] lockedEnd (non-affected, wrap) - OK
    - [Ext] balanceOfAt (affected, wrap) - OK
    - [Pub] getVotes (non-affected, wrap) - OK
    - [Pub] getPastVotes (affected, wrap) - OK
    - [Pub] totalSupply (non-affected, wrap) - OK
    - [Ext] totalSupplyAt (non-affected, wrap) - OK
    - [Pub] totalSupplyLockedAtT (affected, wrap) - OK
    - [Pub] totalSupplyLocked (non-affected, wrap) - OK
    - [Pub] getPastTotalSupply (non-affected, wrap) - OK
    - [Pub] supportsInterface (non-affected, wrap) - OK
    - [Ext] transfer (non-wrap) - OK
    - [Ext] approve (non-wrap) - OK
    - [Ext] transferFrom (non-wrap) - OK
    - [Ext] allowance (non-affected, wrap) - OK
    - [Ext] delegates (non-affected, wrap) - OK
    - [Ext] delegate (non-wrap) - OK
    - [Ext] delegateBySig (non-wrap) - OK

 +  wveOLAS 
    - [Ext] getLastUserPoint 
    - [Ext] getNumUserPoints 
    - [Pub] getUserPoint
    - [Ext] getVotes
    - [Ext] getPastVotes
    - [Ext] balanceOf
    - [Ext] balanceOfAt
    - [Ext] lockedEnd
    - [Ext] totalSupply
    - [Ext] totalSupplyAt
    - [Ext] totalSupplyLockedAtT
    - [Ext] totalSupplyLocked
    - [Ext] getPastTotalSupply
    - [Ext] supportsInterface
    - [Ext] allowance
    - [Ext] delegates
    - [Ext] <Fallback> #

Not implemented in wveOLAS, although logically they should be
        [] name() is view
        [] symbol() is view
        [] decimals() is view
```
[x] (fixed)

### Security issues (instumantal)
Some of the checks are obtained automatically. They are commented and I do not see any serious problems.

All automatic warnings are listed in the following file, concerns of which we address in more detail below:
[slither-full](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal2/analysis/slither_full.txt)

### Needed Improvements and Bugs fixning
No major bugs, but some fixes needed
```
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
Update to actual version.

function balanceOfAt(address account, uint256 blockNumber) external view returns (uint256 balance) {
        // Get the zero account point
        PointVoting memory uPoint = getUserPoint(account, 0);
        // Check that the zero point block number is not smaller than the specified blockNumber
        if (blockNumber >= uPoint.blockNumber) {
            balance = IVEOLAS(ve).balanceOfAt(account, blockNumber);
        }
    }
missing uPoint.blockNumber > 0  && ...?

/// @dev Reverts the allowance of this token.
function allowance(address owner, address spender) external view returns (uint256) {
    return IVEOLAS(ve).allowance(owner, spender);
}
/// @dev Reverts delegates of this token.
function delegates(address account) external view returns (address) {
    return IVEOLAS(ve).delegates(account);
}
these functions always cause a revert on the side of the original veOLAS contract, so you need to do a revert immediately with the original message

Most likely it is better to implement these reverts directly, then this contract will be passed tests for the standard ERC20. (optional)
[ ] transfer(address,uint256) is missing 
[ ] transferFrom(address,address,uint256) is missing 
[ ] approve(address,uint256) is missing
```
[x] (fixed)


 
