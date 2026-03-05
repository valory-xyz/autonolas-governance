# Internal audit of autonolas-governance
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-governance` <br>
commit: `4fd7d98` or `tag: v1.2.5-post-external-audit`<br>

## Objectives
The audit focused on verifying correctness of fixes addressing Code4rena findings related to bridge verification in GuardCM.

### Changed files (contracts/ only)
- contracts/multisigs/bridge_verifier/ProcessBridgedDataArbitrum.sol
- contracts/multisigs/bridge_verifier/ProcessBridgedDataWormhole.sol

### Security issues.
#### Checking the corrections made after Code4rena audit

##### 1. Arbitrum bridge verification ignores retryable-ticket refund/beneficiary parameters, enabling ETH drain from the timelock via callValueRefundAddress
```
Previously, ProcessBridgedDataArbitrum.processBridgeData() decoded the Arbitrum createRetryableTicket
payload but ignored l2CallValue, excessFeeRefundAddress, and callValueRefundAddress parameters.
An attacker could craft a Timelock-scheduled bridge call setting callValueRefundAddress to their own
address, enabling ETH drain from the Timelock.

Fix: ProcessBridgedDataArbitrum.sol now:
- Decodes l2CallValue, excessFeeRefundAddress, callValueRefundAddress (line 66-67)
- Reverts if l2CallValue > 0 via NonZeroValue error (lines 70-72)
- Reverts if excessFeeRefundAddress != l2Timelock via WrongL2BridgeMediator error (lines 75-76)
- Reverts if callValueRefundAddress != l2Timelock via WrongL2BridgeMediator error (lines 78-79)
- The l2Timelock parameter comes from bridgeParams.bridgeMediatorL2 in GuardCM.sol (line 220)

The fix is stricter than the fix note (exact match vs address(0) check), which is correct.
```
[x] Fixed

##### 2. Unchecked refund addresses allow treasury drain via bridges
```
Similar to finding 1, but covers the Wormhole bridge path. ProcessBridgedDataWormhole.processBridgeData()
ignored receiverValue and, for the SEND_MESSAGE_REFUND selector, the refundChainId and refundAddress
parameters. This allowed crafting bridge calls that drain ETH via unchecked refund parameters.

Fix: ProcessBridgedDataWormhole.sol now:
- Adds constants TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE and REFUND_CHAIN_ID = 2 (lines 44-47)
- Decodes receiverValue in both SEND_MESSAGE and SEND_MESSAGE_REFUND branches (lines 84, 89)
- For SEND_MESSAGE_REFUND: reverts if refundChainId != 2 via WrongRefundChainId (lines 93-94)
- For SEND_MESSAGE_REFUND: reverts if refundAddress != TIMELOCK via WrongRefundAddress (lines 96-97)
- Reverts if receiverValue > 0 via NonZeroValue error (lines 102-103)

The Arbitrum part of this finding is covered by finding 1 fix above.
```
[x] Fixed

### Observations on fixed code

#### Notes. Stale comment in GuardCM.sol about Arbitrum bridgeMediatorL2
```
contracts/multisigs/GuardCM.sol:378
Comment says: "Note that bridgeMediatorL2-s can be zero addresses, for example, for Arbitrum case"

The fix in ProcessBridgedDataArbitrum now checks excessFeeRefundAddress and callValueRefundAddress
against l2Timelock (which is bridgeParams.bridgeMediatorL2 from GuardCM). If bridgeMediatorL2 is set
to address(0) for Arbitrum (as the comment suggests is acceptable), the fix would require refund
addresses to be address(0), which is counterproductive — it would enforce the exact vulnerability
the fix aims to prevent.

Recommendation: update the comment to reflect that bridgeMediatorL2 must be set to the actual
L2 aliased Timelock address for Arbitrum, and/or add a non-zero check for bridgeMediatorL2 in
setBridgeMediatorL1BridgeParams when the verifier is ProcessBridgedDataArbitrum.
```
[x] Not fixed
