# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Common Changelog](https://common-changelog.org).

[1.2.5-post-external-audit]: https://github.com/valory-xyz/autonolas-governance/compare/v1.2.3...v1.2.5-post-external-audit
[1.2.3]: https://github.com/valory-xyz/autonolas-governance/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/valory-xyz/autonolas-governance/compare/v1.1.10...v1.2.2
[1.1.10]: https://github.com/valory-xyz/autonolas-governance/compare/v1.1.9...v1.1.10
[1.1.9]: https://github.com/valory-xyz/autonolas-governance/compare/v1.1.8...v1.1.9
[1.1.8]: https://github.com/valory-xyz/autonolas-governance/compare/v1.1.7-post-internal-audit...v1.1.8
[1.1.7]: https://github.com/valory-xyz/autonolas-governance/compare/v1.1.6...v1.1.7-post-internal-audit
[1.1.6]: https://github.com/valory-xyz/autonolas-governance/compare/v1.1.5-pre-audit...v1.1.6
[1.1.5]: https://github.com/valory-xyz/autonolas-governance/compare/v1.1.4...v1.1.5 
[1.1.4]: https://github.com/valory-xyz/autonolas-governance/compare/v1.1.3...v1.1.4
[1.1.3]: https://github.com/valory-xyz/autonolas-governance/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/valory-xyz/autonolas-governance/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/valory-xyz/autonolas-governance/compare/v1.0.1...v1.1.1
[1.0.1]: https://github.com/valory-xyz/autonolas-governance/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/valory-xyz/autonolas-governance/releases/tag/v1.0.0

## [v1.2.5-post-external-audit] - 2026-05-07
- Separated `Timelock` and `GovernorOLAS` execution delays ([#178](https://github.com/valory-xyz/autonolas-governance/pull/178)) with the subsequent internal audit ([audit15](https://github.com/valory-xyz/autonolas-governance/tree/main/audits/internal15) via [#179](https://github.com/valory-xyz/autonolas-governance/pull/179))
- Refactored `WormholeRelayerTimelock` to handle token-amount transfers ([#180](https://github.com/valory-xyz/autonolas-governance/pull/180)) with the subsequent internal audit ([audit16](https://github.com/valory-xyz/autonolas-governance/tree/main/audits/internal16) via [#181](https://github.com/valory-xyz/autonolas-governance/pull/181))
- Added `create_l2_op_olas` script for Optimism L2 OLAS deployment ([#183](https://github.com/valory-xyz/autonolas-governance/pull/183))
- Static audit pass and ownership CSV ([#184](https://github.com/valory-xyz/autonolas-governance/pull/184))
- Participated in the [Code4rena 2026-01](https://code4rena.com/evaluate/j3PRAMM3fVq) external audit (C4A) and addressed the single governance-scope finding (M-01): `ProcessBridgedDataArbitrum` and `ProcessBridgedDataWormhole` now validate retryable-ticket refund/value parameters and reject non-Timelock recipients ([#185](https://github.com/valory-xyz/autonolas-governance/pull/185), [#186](https://github.com/valory-xyz/autonolas-governance/pull/186), [#190](https://github.com/valory-xyz/autonolas-governance/pull/190), [#192](https://github.com/valory-xyz/autonolas-governance/pull/192))
- Internal audits verifying the C4A fixes and re-checking governance-scope ([audit17](https://github.com/valory-xyz/autonolas-governance/tree/main/audits/internal17), [audit18](https://github.com/valory-xyz/autonolas-governance/tree/main/audits/internal18), [audit19](https://github.com/valory-xyz/autonolas-governance/tree/main/audits/internal19) via [#189](https://github.com/valory-xyz/autonolas-governance/pull/189), [#193](https://github.com/valory-xyz/autonolas-governance/pull/193), [#194](https://github.com/valory-xyz/autonolas-governance/pull/194), [#195](https://github.com/valory-xyz/autonolas-governance/pull/195))
- Restored EIP-170 compliance in `GuardCM` after the audit-driven changes ([#195](https://github.com/valory-xyz/autonolas-governance/pull/195))
- Added Forge deployment scripts for `GuardCM`, the `ProcessBridgedData{Arbitrum,Gnosis,Optimism,Polygon}` bridge verifiers (`deploy_26_*`) and `GovernorOLAS` (`deploy_27_*`), plus matching `setBridgeMediatorL1BridgeParams` configuration scripts ([#187](https://github.com/valory-xyz/autonolas-governance/pull/187))
- Added `ForkDeployGovernance` Forge fork test validating the deployment scripts against mainnet state ([#187](https://github.com/valory-xyz/autonolas-governance/pull/187))
- Migrated `Vulnerabilities_list_governance` from PDF to markdown with relative links ([#191](https://github.com/valory-xyz/autonolas-governance/pull/191))
- Fixed OLAS-on-Celo address in documentation ([#188](https://github.com/valory-xyz/autonolas-governance/pull/188))

## [v1.2.3] - 2024-11-01
- Deployed `Burner` contract on ETH mainnet ([#160](https://github.com/valory-xyz/autonolas-governance/pull/160))
- Deployed `OptimismMessenger` to Mode ([#158](https://github.com/valory-xyz/autonolas-governance/pull/158))
- Adjusting static audit

## [v1.2.2] - 2024-07-29
- Created and deployed `VoteWeighting` contract as part of the [PoAA](https://staking.olas.network/poaa-whitepaper.pdf) requirement ([#150](https://github.com/valory-xyz/autonolas-governance/pull/150))
- Participated in a complete [C4R audit competition](https://github.com/code-423n4/2024-05-olas-findings) and addressed findings

## [v1.1.10] - 2024-03-08
- Created `OptimismMessenger` contract to serve as a bridge mediator on Optimism and Base networks ([#114](https://github.com/valory-xyz/autonolas-governance/pull/114/files))
- Created `WormholeMessenger` contracts to serve as a bridge mediator on Celo and other L2 networks ([#116](https://github.com/valory-xyz/autonolas-governance/pull/116/files))
- Deploying `OptimismMessenger` to Optimism and Base, deploying `WormholeMessenger` on Celo
- Updated documentation
- Tests coverage

## [v1.1.9] - 2024-01-19
- Refactor `GuardCM` reacting to C4A findings ([#107](https://github.com/valory-xyz/autonolas-governance/pull/107/files))
- Deployment of refactored `GuardCM` contract
- Deployment of ERC20 bridge infrastructure contracts between ETH and Polygon ([#106](https://github.com/valory-xyz/autonolas-governance/pull/106/files))
- Updated documentation
- Tests coverage

## [v1.1.8] - 2023-12-18
- Updated the implementation of `GuardCM` contract for community multisig (CM) guard ([#101](https://github.com/valory-xyz/autonolas-governance/pull/101/files))
- Updated documentation
- Tests coverage
- Refactor `GuardCM` contract ([#104](https://github.com/valory-xyz/autonolas-governance/pull/104)) reacting to the internal audit ([audit8](https://github.com/valory-xyz/autonolas-governance/tree/main/audits/internal8))


## [v1.1.7-post-internal-audit] - 2023-11-30
- Created and deployed ERC20 token bridging contracts to Polygon mumbai and Ethereum goerli testnets ([#95](https://github.com/valory-xyz/autonolas-governance/pull/95))
- Updated documentation and deployment scripts
- Added unit tests, coverage and bridging integration test scripts
- Refactor and tests for ERC20 token bridging contracts ((#97)[https://github.com/valory-xyz/autonolas-governance/pull/97]) reacting to the internal audit ([audit7](https://github.com/valory-xyz/autonolas-governance/tree/main/audits/internal7))

## [1.1.6] - 2023-09-07

### Changed
- Created and deployed `GuardCM` contract for community multisig (CM) guard ([#83](https://github.com/valory-xyz/autonolas-governance/pull/83))
  with the subsequent internal audit ([audit6](https://github.com/valory-xyz/autonolas-governance/tree/main/audits/internal6))
  
## [1.1.5] - 2023-10-04

### Changed

_No bytecode changes_.

- Added last external audit  
- Updated audit contract setup script
- Updated documentation
- Created proposal scripts
- Created script to check on-chain configurations 

## [1.1.4] - 2023-06-21

### Changed

- Updated and deployed `GovernorOLAS` that was refactored based on the OpenZeppelin contracts version 4.8.3 ([#76](https://github.com/valory-xyz/autonolas-governance/pull/76))
  with the subsequent internal audit ([audit5](https://github.com/valory-xyz/autonolas-governance/tree/main/audits/internal5))

## [1.1.3] - 2023-05-19

### Changed

- Created and deployed `HomeMediator` contract that acts as a bridge mediator between Ethereum and Gnosis chains ([#69](https://github.com/valory-xyz/autonolas-governance/pull/69))
  with the subsequent internal audit ([audit4](https://github.com/valory-xyz/autonolas-governance/tree/main/audits/internal4))

## [1.1.2] - 2023-04-21

_No bytecode changes_.

### Changed

- Updated documentation and contract addresses

## [1.1.1] - 2023-04-13

### Changed

- Created and deployed `wveOLAS` contract that wraps veOLAS functionality with a couple of corrected view functions ([#52](https://github.com/valory-xyz/autonolas-governance/pull/52))
  with the subsequent internal audit ([audit2](https://github.com/valory-xyz/autonolas-governance/tree/main/audits/internal2))
- Created and deployed `FxGovernorTunnel` contract that acts as a bridge mediator between Ethereum and Polygon chains ([#58](https://github.com/valory-xyz/autonolas-governance/pull/58))
  with the subsequent internal audit ([audit3](https://github.com/valory-xyz/autonolas-governance/tree/main/audits/internal3))

## [1.0.1] - 2022-12-09

### Changed

- Updated NatSpec comments in contracts
- Updated documentation
- Added more tests
- Addressed known vulnerabilities

## [1.0.0] - 2022-06-30

### Added

- Initial release