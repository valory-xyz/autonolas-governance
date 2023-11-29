# autonolas-governance-audit
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-governance` <br>
commit: `93c03a22e1dabfc6cbe70c050d804ea2f903d5c2` or `tag: v1.1.7-pre-internal-audit` <br> 

Update: 27-11-2023  <br>

## Objectives
The audit focused on ERC20 bridging. <BR>

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal7/analysis/contracts)

### Coverage
Hardhat coverage has been performed before the audit and can be found here:
```sh
 contracts/bridges/      |    93.42 |      100 |       95 |    95.24 |                |
  BridgedERC20.sol       |      100 |      100 |      100 |      100 |                |
  FxERC20ChildTunnel.sol |      100 |      100 |      100 |      100 |                |
  FxERC20RootTunnel.sol  |    66.67 |      100 |       80 |    71.43 |... 70,72,82,84 |
```
Notes: Pay attention to coverage FxERC20RootTunnel.sol

### Security issues
Details in [slither_full](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal7/analysis/slither_full.txt) <br>

#### Bug in constructor: 
```solidity
Compilation warnings/errors on ./BridgedERC20-flatten.sol:
Warning: Unused function parameter. Remove or comment out the variable name to silence this warning.
   --> BridgedERC20-flatten.sol:231:38:
    |
231 |     constructor(string memory _name, string memory _symbol) ERC20(_name, symbol, 18) {

as result of typo
constructor(string memory _name, string memory _symbol) ERC20(_name, symbol, 18) {

=> ERC20(_name, symbol, 18)
correct
ERC20(_name, _symbol, 18)

decimals (18) as constant is OK?
```
[x] fixed

#### Reentrancy (not critical since the token is trusted, but it’s better to fix the problem)
```solidity
function depositTo(address to, uint256 amount) external {
        // Check for the address to deposit tokens to
        if (to == address(0)) {
            revert ZeroAddress();
        }

        _deposit(to, amount);
    }
    if (amount == 0) {
            revert ZeroValue();
        }

        // Deposit tokens on an L2 bridge contract (lock)
        IERC20(childToken).transferFrom(msg.sender, address(this), amount); --> reentrancy
    
```
Notes: It is better to use explicit protection like reentrancy_guard_variable than CEI. <br>
[x] fixed

#### Non-checked return
```solidity
unchecked-transfer
        // Transfer decoded amount of tokens to a specified address
        IERC20(childToken).transfer(to, amount);

```
[x] fixed

#### Non-checked return
```solidity
unchecked-transfer
        // Transfer tokens from sender to this contract address
        IERC20(rootToken).transferFrom(msg.sender, address(this), amount);

```
[x] fixed

#### Overengineering
```solidity
Unnecessarily overcomplicated part with cast to uint96 + abi.encodePacked It is not recommended to use unless absolutely necessary.
https://docs.soliditylang.org/en/latest/abi-spec.html#non-standard-packed-mode

bytes memory message = abi.encodePacked(msg.sender, to, uint96(amount));
https://github.com/pessimistic-io/slitherin/blob/master/docs/dubious_typecast.md
+
no-inline-assembly
I'm not sure that it is necessary to parse using assembler
```
[x] fixed