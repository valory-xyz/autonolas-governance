# autonolas-governance-audit
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-governance` <br>
commit: `50a336a2e31f980399f8c84ba6dad9cb9c673aaa` or `v1.1.10-pre-internal-audi` <br> 

Update: 28-02-2024  <br>

## Objectives
The audit focused on governance using native bridging to Optimism/Base and Wormhole bridging to EVM-networks supported by Standard Relayer. <BR>

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal9/analysis/contracts)

### Coverage
Hardhat coverage has been performed before the audit and can be found here:
```sh
---------------------------|----------|----------|----------|----------|----------------|
File                       |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
  OptimismMessenger.sol    |        0 |        0 |        0 |        0 |... 163,164,169 |
  WormholeMessenger.sol    |        0 |        0 |        0 |        0 |... 201,202,207 |
```
Pay attention, please! No tests for contract on scope.
[x] Fixed

#### Wormhole security list
https://docs.wormhole.com/wormhole/quick-start/cross-chain-dev/standard-relayer#other-considerations
```
Receiving a message from relayer 
 Check for expected emitter [x]
 call parseAndVerify on any additionalVAAs [N/A]
Replay protection [x]
Message Ordering 
 no guarantees on order of messages delivered [?] - requires discussion
Fowarding/Call Chaining - [x], by design
Refunding overpayment of gasLimit - [?] - requires discussion
Refunding overpayment of value sent - [?] - requires discussion
ref: https://github.com/wormhole-foundation/hello-wormhole/blob/main/src/extensions/HelloWormholeRefunds.sol
```
[x] Good point, need to set up these parameters and call the corresponding function on the L1 Relayer (added to test scripts)

### Security issues
Details in [slither_full](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/internal9/analysis/slither_full.txt) <br>
Notes: <br>
All is false positive.

### Possible optimization
##### Avoid casting
```
    // Source governor address on L1 that is authorized to propagate the transaction execution across the bridge
    address public sourceGovernor;
=>
set sourceGovernor in wormhole address format as bytes32
so avoid casting bytes32 to address EVM.
        // Check for the source governor address
        bytes32 governor = sourceGovernor;
        if (governor != sourceAddress) {
            revert SourceGovernorOnly(bridgeGovernor, governor);
        }
ref: https://github.com/wormhole-foundation/wormhole-solidity-sdk/blob/main/src/Base.sol#L30C52-L30C74 SDK of Wormhole
```
[x] Fixed

##### Re-design contracts
Part of the code is common and has the nature of a repeatable pattern for all contracts. <br>
It makes sense to separate it into a separate contract and replace magic numbers (20,12,4) with constants.
```
// Check for the correct data length
        uint256 dataLength = data.length;
        if (dataLength < DEFAULT_DATA_LENGTH) {
            revert IncorrectDataLength(DEFAULT_DATA_LENGTH, data.length);
        }

        // Unpack and process the data
        for (uint256 i = 0; i < dataLength;) {
            address target;
            uint96 value;
            uint32 payloadLength;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                // First 20 bytes is the address (160 bits)
                i := add(i, 20)
                target := mload(add(data, i))
                // Offset the data by 12 bytes of value (96 bits)
                i := add(i, 12)
                value := mload(add(data, i))
                // Offset the data by 4 bytes of payload length (32 bits)
                i := add(i, 4)
                payloadLength := mload(add(data, i))
            }

            // Check for the zero address
            if (target == address(0)) {
                revert ZeroAddress();
            }

            // Check for the value compared to the contract's balance
            if (value > address(this).balance) {
                revert InsufficientBalance(value, address(this).balance);
            }

            // Get the payload
            bytes memory payload = new bytes(payloadLength);
            for (uint256 j = 0; j < payloadLength; ++j) {
                payload[j] = data[i + j];
            }
            // Offset the data by the payload number of bytes
            i += payloadLength;

            // Call the target with the provided payload
            (bool success, ) = target.call{value: value}(payload);
            if (!success) {
                revert TargetExecFailed(target, value, payload);
            }
        }
```
[x] Fixed







 
