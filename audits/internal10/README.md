# autonolas-governance-audit
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-governance` <br>
commit: `bde297d7dbb601fbe796f56fe03e917d60282cd0` or `tag: v1.1.11-pre-internal-audit` <br> 

Update: 06-03-2024  <br>

## Objectives
The audit focused on Guard contract for community mutisig (modular version). <BR>

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal10/analysis/contracts)

### Coverage
Hardhat coverage has been performed before the audit and can be found here:
```sh
--------------------------------------|----------|----------|----------|----------|----------------|
File                                  |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
--------------------------------------|----------|----------|----------|----------|----------------|
 contracts/multisigs/                 |    98.18 |    96.15 |      100 |       99 |                |
  GuardCM.sol                         |    98.11 |    96.05 |      100 |    98.95 |            223 |
  VerifyData.sol                      |      100 |      100 |      100 |      100 |                |
 contracts/multisigs/bridge_verifier/ |    49.12 |    47.37 |       50 |    49.44 |                |
  ProcessBridgedDataArbitrum.sol      |        0 |        0 |        0 |        0 |... 55,56,60,64 |
  ProcessBridgedDataGnosis.sol        |      100 |      100 |      100 |      100 |                |
  ProcessBridgedDataOptimism.sol      |        0 |        0 |        0 |        0 |... 75,76,80,83 |
  ProcessBridgedDataPolygon.sol       |      100 |      100 |      100 |      100 |                |
  ProcessBridgedDataWormhole.sol      |        0 |        0 |        0 |        0 |... 67,72,73,77 |
  VerifyBridgedData.sol               |      100 |      100 |      100 |      100 |                |
--------------------------------------|----------|----------|----------|----------|----------------|
```
Please, pay attention. More tests are needed and magic offsets (like MIN_ARBITRUM_PAYLOAD_LENGTH) can only be checked during testing
[x] fixed

### Storage timelock
Using sol2uml tools: https://github.com/naddison36/sol2uml <br>
```bash
sol2uml storage . -f png -c GuardCM -o .
Generated png file GuardCM.png
```
Storage: [GuardCM](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal10/analysis/GuardCM.png)

### Security issues
Details in [slither_full](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal10/analysis/slither_full.txt) <br>
All is false positive, discussed https://github.com/pessimistic-io/slitherin/blob/master/docs/arbitrary_call.md

Minor issue: <br>
- Cached bytes4(data)
```
Dubious typecast in VerifyData._verifyData(address,bytes,uint256) (ProcessBridgedDataArbitrum-flatten.sol#25-38):
	bytes => bytes4 casting occurs in targetSelectorChainId |= uint256(uint32(bytes4(data))) << 160 (ProcessBridgedDataArbitrum-flatten.sol#30)
	bytes => bytes4 casting occurs in revert NotAuthorized(address,bytes4,uint256)(target,bytes4(data),chainId) (ProcessBridgedDataArbitrum-flatten.sol#36)
```
[x] fixed

- Checking for verifierL2s is contract in set function.
```
function setBridgeMediatorL1BridgeParams(
if (verifierL2s[i].code.length == 0) {
    revert AddressEmptyCode(verifierL2s[i]);
}
because if verifierL2s[i] is EOA
bridgeParams.verifierL2.delegatecall - always success, 
ref: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Address.sol#L124
```
[x] fixed

- Needing fix revert message
```
Code correct. Ref: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Address.sol#L146
revert("Function call reverted");
replace to error-style message 
revert FailedInnerCall();
```
[x] fixed
