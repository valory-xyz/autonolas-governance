# autonolas-governance-audit
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-governance` <br>
commit: `9838942c824f0a5f2ead48e299c4ba465050e1ad` or `v1.1.8-pre-internal-audi` <br> 

Update: 15-12-2023  <br>

## Objectives
The audit focused on update Guard contract for community mutisig (L2 protection). <BR>

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal8/analysis/contracts)

### Coverage
Hardhat coverage has been performed before the audit and can be found here:
```sh
-------------------------|----------|----------|----------|----------|----------------|
File                     |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-------------------------|----------|----------|----------|----------|----------------|
 contracts/              |      100 |    93.75 |      100 |    98.68 |                |
 contracts/multisigs/    |    59.15 |    57.69 |    83.33 |    59.66 |                |
  GuardCM.sol            |    59.15 |    57.69 |    83.33 |    59.66 |... 327,364,367 |
-------------------------|----------|----------|----------|----------|----------------|
All files                |    91.15 |    87.07 |    97.14 |     91.8 |                |
-------------------------|----------|----------|----------|----------|----------------|
```
Pay attention, please.  

### Storage timelock
Using sol2uml tools: https://github.com/naddison36/sol2uml <br>
```bash
sol2uml storage . -f png -c GuardCM -o .
Generated png file GuardCM.png
```
Storage: [GuardCM](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal8/analysis/GuardCM.png)

### Security issues
Details in [slither_full](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal8/analysis/slither_full.txt) <br>

Notes: <br>
- chainIds[i] in constructor not checked by zero. 

- No update method (with event) for bridge map, like setTargetSelectors(). <br>
Most likely this is not practical, since adding new L2-chains (or bridges) inevitably entails changing the custom logic in _processBridgeData(). <br>
For discussion
```
Only via constructor (re-deploy) we can update mapBridgeMediator ...
Perhaps update methods does not make sense because custom logic is needed inside function _processBridgeData() for new/updated bridges.
A clear comment about this needs to be added.
```
[x] fixed

- Assumed that the checked data in _verifyData() always exists (data.length > 0). For discussion
```
function _verifyData(address target, bytes memory data) internal view {
        // Push a pair of key defining variables into one key
        // target occupies first 160 bits
        uint256 targetSelector = uint256(uint160(target));
        // selector occupies next 32 bits
        targetSelector |= uint256(uint32(bytes4(data))) << 160;

        // Check the authorized combination of target and selector
        if (!mapAllowedTargetSelectors[targetSelector]) {
            revert NotAuthorized(target, bytes4(data));
        }
    }

so, case _to.call{value: msg.value}("") makes the situation uncertain.
1. is this allowed for the case L1?
2. is this allowed for the case L2 (bridge)?
clearer processing needed
```
[x] fixed

- dataLength < DEFAULT_DATA_LENGTH Does it make sense to check earlier? For discussion
```
for check size before call abi.decode(payload, (address, bytes, uint256));
i.e. // Check for the correct data length
uint256 dataLength = For discussion;
if (dataLength < DEFAULT_DATA_LENGTH) {
    revert IncorrectDataLength(DEFAULT_DATA_LENGTH, data.length);
}
moved to _processBridgeData  with modification 
```
[x] fixed

- Pay attention to memory cleaning. For discussion
```
bytes memory payload = new bytes(data.length - 4);
payload = new bytes(mediatorPayload.length - 4);
Should we do some kind of memory explicity cleaning?
```
[x] fixed

- "shared" mapAllowedTargetSelectors for all chains. For discussion
```
The current approach implies that
allowed (addr1 + selector func1) is allowed in any chains
so, if you allowed addr1 + selector func1 for L1 this implies that you have enabled it for the L2 (polygon as example) as well. and vice versa

Alternative method, change the algorithm generation of targetSelector: old + chainId. size of chainId = 64bit. so, targetSelector = 160+32+64 = 256.
uint256 targetSelector = uint256(uint160(target));
// selector occupies next 32 bits
targetSelector |= uint256(uint32(bytes4(data))) << 160;
+
targetSelector |= uint256(chainId) << 192;
```
[x] fixed







 
