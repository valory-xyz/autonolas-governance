# Autonolas Governance & Tokens

## Bounty Program
:mega::satellite::boom: The Autonolas bounty program and its details are available [here](https://immunefi.com/bounty/autonolas/).

## Introduction
This repository contains the Autonolas `OLAS` token and the governance part of the on-chain protocol.

A graphical overview of the whole on-chain architecture is available here:

![architecture](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/On-chain_architecture_v5.png?raw=true)
Please note that `buOLAS` contract is not part of the diagram.

We follow the standard governance setup by OpenZeppelin. Our governance token is a voting escrow token (`veOLAS`) created by locking `OLAS`.

An overview of the design is provided [here](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/Governance_process.pdf?raw=true) and the contracts' specifications are provided [here](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/Specs%20of%20governance%20contracts_v1.1.0.pdf?raw=true).

- [OLAS](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/OLAS.sol);
- [VotingEscrow (veOLAS)](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/veOLAS.sol);
- [GovernorOLAS](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/GovernorOLAS.sol);
- [Timelock](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/Timelock.sol).

For team incentivisation we have a burnable locked `OLAS` token - `buOLAS`:
- [buOLAS](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/buOLAS.sol).

In order to deploy OLAS and veOLAS contracts via the create2() method, the following contract is utilized for vanity addresses:
- [DeploymentFactory](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/DeploymentFactory.sol).

To address several found `veOLAS` contract view functions issues, a wrapper contract `wveOLAS` is implemented:
- [veOLAS wrapper (wveOLAS)](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/wveOLAS.sol).

The changelog leading to the implementation of `wveOLAS` can be found here: [Changelog_v1.1.0](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/Changelog_v1.1.0.pdf?raw=true)

To complement, a list of known vulnerabilities can be found here: [Vulnerabilities list](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/Vulnerabilities_list_governance.pdf?raw=true)

In order to manage cross-bridge transactions via the `Timelock` contract on the Polygon network, the Fx Governor Tunnel contract is implemented:
- [FxGovernorTunnel](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/bridges/FxGovernorTunnel.sol).

In order to manage cross-bridge transactions via the `Timelock` contract on the Gnosis network, the Home Mediator contract is implemented:
- [HomeMediator](https://github.com/valory-xyz/autonolas-governance/blob/main/contracts/bridges/HomeMediator.sol).

The functionality thereby enabled is outlined in detail here: [Cross-chain governance: from Ethereum to Polygon](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/governace_bridge.pdf?raw=true).


## Development

### Prerequisites
- This repository follows the standard [`Hardhat`](https://hardhat.org/tutorial/) development process.
- The code is written on Solidity starting from version `0.8.15`.
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
Run the Voting Escrow forking tests (please make sure the `ALCHEMY_API_KEY` environmental variable is set):
```
npm run fork
```

### Docker

If you are running using amd64 (eg. Mac M1), please export the newly build image from the docker-build image.
You can find more information [here](https://docs.docker.com/build/building/multi-platform/).
```
docker buildx create --name amdBuilder --driver docker-container --bootstrap
docker buildx use amdBuilder
```

To build the docker image:
```
docker buildx build --platform linux/amd64 -t valory/autonolas-governance:dev . --load
```

To build the docker image with the default docker engine:
```
docker build -t valory/autonolas-governance:dev .
```

To run the docker image:
```
docker run -p 8545:8545 -it valory/autonolas-governance:dev
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

### Comparison of veOLAS and Curve Voting Escrow (veCRV) contracts via forking
Several test scripts have been written in order to compare the behavior of veOLAS and veCRV, which can be found here:
[veCompare](https://github.com/valory-xyz/autonolas-governance/blob/main/scripts/veCompare).

The original Voting Escrow ABI is located here: [veCRV ABI](https://github.com/valory-xyz/autonolas-governance/blob/main/abis/test/veCRV.json).
One can run the forking test via the `npm run fork` command as described above.

## Deployment of Core Contracts
The deployment of contracts to the test- and main-net is split into step-by-step series of scripts for more control and checkpoint convenience.
The description of deployment procedure can be found here: [deployment](https://github.com/valory-xyz/autonolas-governance/blob/main/scripts/deployment).

The finalized contract ABIs for deployment and their number of optimization passes are located here:
[ABIs](https://github.com/valory-xyz/autonolas-governance/blob/main/abis).

## Bridges

### Cross-chain governance
Depending on the network, the cross-chain functionalities enabled are outlined in detail here:
[Cross-chain governance](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/governace_bridge.pdf?raw=true).

In order to correctly pack the data and supply it to the Timelock such that it is correctly processed across the bridge,
use the following script: [cross-bridge data packing](https://github.com/valory-xyz/autonolas-governance/blob/main/scripts/deployment/bridges/pack_data.js).

#### Polygon governance bridge 
Autonolas will use the [FxPortal](https://github.com/fx-portal/contracts) developed and designed by the Polygon team to support cross-chain bridging from Ethereum to Polygon.

For running a test between `goerli` and `mumbai`, run the test script with your own credentials:
[`goerli-mumbai` hello world bridge test](https://github.com/valory-xyz/autonolas-governance/blob/main/scripts/deployment/bridges/polygon/test/fx_goerli_mumbai_hello_world.js)
and [`goerli-mumbai` governor bridge test](https://github.com/valory-xyz/autonolas-governance/blob/main/scripts/deployment/bridges/polygon/test/fx_goerli_mumbai_governor.js).
Note that the script must be run without Hardhat environment, i.e.: `node test_script.js`.

#### Gnosis governance bridge
Autonolas will use the [Arbitrary Message Bridge](https://docs.gnosischain.com/bridges/tokenbridge/amb-bridge) developed
and designed by the Gnosis team to support cross-chain bridging from Ethereum to Gnosis Chain.

For running a test between `goerli` and `chiado`, run the test script with your own credentials:
[`goerli-chiado` hello world bridge test](https://github.com/valory-xyz/autonolas-governance/blob/main/scripts/deployment/bridges/gnosis/test/mediator_goerli_chiado_hello_world.js)
and [`goerli-chiado` governor bridge test](https://github.com/valory-xyz/autonolas-governance/blob/main/scripts/deployment/bridges/polygon/test/mediator_goerli_chiado_governor.js).
Note that the script must be run without Hardhat environment, i.e.: `node test_script.js`.

### ERC20 token bridging between Polygon and Ethereum
The contract design facilitating token bridging between the Polygon and Ethereum networks, along with the underlying motivations driving the creation of these contracts, is outlined here:
[Bridging token](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/Bonding_mechanism_with_Polygon_LP_token.pdf?raw=true). 

### Deployment of bridge-related contracts
The description of bridge-related deployment procedure is very similar to the original deployment process and can be found here:
- [bridges-polygon](https://github.com/valory-xyz/autonolas-governance/blob/main/scripts/deployment/bridges/polygon);
- [bridges-gnosis](https://github.com/valory-xyz/autonolas-governance/blob/main/scripts/deployment/bridges/gnosis).

The description of ERC20 token bridging deployment between Polygon and Ethereum can be found here:
[deployment](https://github.com/valory-xyz/autonolas-governance/blob/main/scripts/deployment).

## Documents
All the project-related documents are located here: [docs](https://github.com/valory-xyz/autonolas-governance/blob/main/docs).

### Code optimizations and best practices
The list of optimization considerations and best practices exercised during the development of Autonolas governance
can be found [here](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/optimizations.md).

### Audits
- The audit is provided as development matures. The latest audit report can be found here: [audits](https://github.com/valory-xyz/autonolas-governance/blob/main/audits).
- The list of known vulnerabilities can be found here: [Vulnerabilities list #1](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/Vulnerabilities_list%231.pdf?raw=true).

### Deployed Protocol
The list of contract addresses for different chains and their full contract configuration can be found [here](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/configuration.json).

In order to test the protocol setup on all the deployed chains, the audit script is implemented. Make sure to export
required API keys for corresponding chains (see the script for more information). The audit script can be run as follows:
```
node scripts/audit_chains/audit_contracts_setup.js
```

## Acknowledgements
The Autonolas `OLAS` contract was inspired and based on in parts by the following sources:
- [Rari-Capital](https://github.com/Rari-Capital/solmate). Last known audited version: `a9e3ea26a2dc73bfa87f0cb189687d029028e0c5`;
- [Maple Finance](https://github.com/maple-labs/erc20). Last known audited version: `756c110ddc3c96c596a52bce43553477a19ee3aa`;

The `veOLAS` contract was inspired and based on the following sources:
- [Curve DAO](https://github.com/curvefi/curve-dao-contracts).

The governance contracts and the rest was inspired and based on the following sources:
- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts).

The bridging contracts were based on and inspired by the following sources:
- [Polygon](https://github.com/maticnetwork).
- [fx-portal](https://github.com/fx-portal).
- [Gnosis Chain Docs](https://docs.gnosischain.com/bridges/tokenbridge/amb-bridge).
