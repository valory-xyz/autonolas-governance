# Autonolas Governance & Tokens

## Bounty Program
:mega::satellite::boom: The Autonolas bounty program and its details are available [here](https://immunefi.com/bounty/autonolas/).

## Introduction
This repository contains the Autonolas `OLAS` token and the governance part of the on-chain protocol.

A graphical overview of the whole on-chain architecture is available here:

![architecture](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/On-chain_architecture.png?raw=true)
Please note that `buOLAS` and `Sale` contracts are not part on the diagram.

We follow the standard governance setup by OpenZeppelin. Our governance token is a voting escrow token (`veOLAS`) created by locking `OLAS`.

An overview of the design is provided [here](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/Governance_process.pdf?raw=true) and the contracts' specifications are provided [here](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/Specs%20of%20governance%20contracts_v1.0.1.pdf?raw=true).

- [OLAS](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/OLAS.sol)
- [VotingEscrow (veOLAS)](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/veOLAS.sol)
- [GovernorOLAS](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/GovernorOLAS.sol)
- [Timelock](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/Timelock.sol)

For team incentivisation we have a burnable locked `OLAS` token - `buOLAS`:
- [buOLAS](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/buOLAS.sol)

For initial incentivised locking of `OLAS` tokens we have a `Sale` contract - `Sale`:
- [Sale](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/Sale.sol)

In order to deploy OLAS and veOLAS contracts via the create2() method, the following contract is utilized for vanity addresses:
- [DeploymentFactory](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/DeploymentFactory.sol)

## Development

### Prerequisites
- This repository follows the standard [`Hardhat`](https://hardhat.org/tutorial/) development process.
- The code is written on Solidity `0.8.15`.
- The standard versions of Node.js along with Yarn are required to proceed further (confirmed to work with Yarn `1.22.10` and npx/npm `6.14.11` and node `v12.22.0`).

### Install the dependencies
The project has submodules to get the dependencies. Make sure you run `git clone --recursive` or init the submodules yourself.
The dependency list is managed by the `package.json` file,
and the setup parameters are stored in the `hardhat.config.js` file.
Simply run the following command to install the project:
```
yarn install
```

### Core components
The contracts and tests are located in the following folders respectively:
```
contracts
test
```

### Compile the code and run
Compile the code:
```
npx hardhat compile
```
Run the tests:
```
npx hardhat test
```

### Linters
- [`ESLint`](https://eslint.org) is used for JS code.
- [`solhint`](https://github.com/protofire/solhint) is used for Solidity linting.


### Github Workflows
The PR process is managed by github workflows, where the code undergoes
several steps in order to be verified. Those include:
- code installation
- running linters
- running tests

## Deployment
The deployment of contracts to the test- and main-net is split into step-by-step series of scripts for more control and checkpoint convenience.
The description of deployment procedure can be found here: [deployment](https://github.com/valory-xyz/autonolas-governance/blob/main/scripts/deployment).

The finalized contract ABIs for deployment and their number of optimization passes are located here: [ABIs](https://github.com/valory-xyz/autonolas-governance/blob/main/abis).

## Code optimizations and best practices
The list of optimization considerations and best practices exercised during the development of Autonolas governance
can be found [here](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/optimizations.md).

## Audits
The audit is provided as development matures. The latest audit report can be found here: [audits](https://github.com/valory-xyz/autonolas-governance/blob/main/audits).
A list of known vulnerabilities can be found here: [Vulnerabilities list #1](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/Vulnerabilities_list%231.pdf)

## Deployed Protocol
The list of addresses can be found [here](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/mainnet_addresses.json).

## Acknowledgements
The Autonolas `OLAS` contract was inspired and based on in parts by the following sources:
- [Rari-Capital](https://github.com/Rari-Capital/solmate). Last known audited version: `a9e3ea26a2dc73bfa87f0cb189687d029028e0c5`;
- [Maple Finance](https://github.com/maple-labs/erc20). Last known audited version: `756c110ddc3c96c596a52bce43553477a19ee3aa`;

The `veOLAS` contract was inspired and based on the following sources:
- [Curve DAO](https://github.com/curvefi/curve-dao-contracts).

The governance contracts and the rest was inspired and based on the following sources:
- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts).
