# Autonolas Governance

## Introduction

This repository contains the Autonolas OLA token and the governance part of the on-chain protocol.

A graphical overview of the whole on-chain architecture is available here:

![architecture](https://github.com/valory-xyz/onchain-protocol/blob/main/docs/On-chain_architecture_v2.png?raw=true)

We follow the standard governance setup by OpenZeppelin. Our governance token is a voting escrow token.

An overview of the design is provided [here](https://github.com/valory-xyz/onchain-protocol/blob/main/docs/Audit_Governance.pdf?raw=true).

- [OLA](https://github.com/valory-xyz/autonolas-governancel/blob/main/contracts/OLA.sol)
- [VotingEscrow (veOLA)](https://github.com/valory-xyz/autonolas-governancel/blob/main/contracts/VotingEscrow.sol)
- [GovernorOLA](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/GovernorOLA.sol)
- [Timelock](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/Timelock.sol)
- [buOLA](https://github.com/valory-xyz/autonolas-governancel/blob/main/contracts/buOLA.sol)

## Development

### Prerequisites
- This repository follows the standard [`Hardhat`](https://hardhat.org/tutorial/) development process.
- The code is written on Solidity `0.8.14`.
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

### Internal audit
The audit is provided internally as development matures. The latest audit report can be found here: [audit](https://github.com/valory-xyz/onchain-protocol/blob/main/audit).

### Linters
- [`ESLint`](https://eslint.org) is used for JS code.
- [`solhint`](https://github.com/protofire/solhint) is used for Solidity linting.


### Github workflows
The PR process is managed by github workflows, where the code undergoes
several steps in order to be verified. Those include:
- code isntallation
- running linters
- running tests


## Acknowledgements

The Autonolas OLA contract was inspired and based on in parts by the following sources:
- [Rari-Capital](https://github.com/Rari-Capital/solmate). Last known audited version: `a9e3ea26a2dc73bfa87f0cb189687d029028e0c5`;
- [Maple Finance](https://github.com/maple-labs/erc20). Last known audited version: `756c110ddc3c96c596a52bce43553477a19ee3aa`;
- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts). Last known audited version: `136710cdd4a7b10e93b1774f086a89133f719ebe`.