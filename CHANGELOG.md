# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Common Changelog](https://common-changelog.org).

[1.1.4]: https://github.com/valory-xyz/autonolas-governance/compare/v1.1.3...v1.1.4
[1.1.3]: https://github.com/valory-xyz/autonolas-governance/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/valory-xyz/autonolas-governance/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/valory-xyz/autonolas-governance/compare/v1.0.1...v1.1.1
[1.0.1]: https://github.com/valory-xyz/autonolas-governance/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/valory-xyz/autonolas-governance/releases/tag/v1.0.0

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