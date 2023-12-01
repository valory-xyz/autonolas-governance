# Deployment scripts
This folder contains the scripts to deploy Autonolas governance. These scripts correspond to the steps in the full deployment procedure (as described in [deployment.md](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/deployment.md)).

## Observations
- There are several files with global parameters based on the corresponding network. In order to work with the configuration, please copy `gobals_network.json` file to file the `gobals.json` one, where `network` is the corresponding network. For example: `cp gobals_goerli.json gobals.json`.
- The Valory multisig (Valory) is a Gnosis Safe contract with 3 signers and 2 threshold that already exists.
- The community multisig (CM) of the DAO is a Gnosis Safe contract with 9 signers and 6 threshold that already exists.
- Please note: if you encounter the `Unknown Error 0x6b0c`, then it is likely because the ledger is not connected or logged in.

## Steps to engage
The project has submodules to get the dependencies. Make sure you run `git clone --recursive` or init the submodules yourself.
The dependency list is managed by the `package.json` file, and the setup parameters are stored in the `hardhat.config.js` file.
Simply run the following command to install the project:
```
yarn install
```
command and compiled with the
```
npx hardhat compile
```
command as described in the [main readme](https://github.com/valory-xyz/autonolas-governance/blob/main/README.md).


Create a `globals.json` file in the root folder, or copy it from the file with pre-defined parameters (i.e., `scripts/deployment/globals_goerli.json` for the goerli testnet).

Parameters of the `globals.json` file:
- `contractVerification`: a flag for verifying contracts in deployment scripts (`true`) or skipping it (`false`);
- `useLedger`: a flag whether to use the hardware wallet (`true`) or proceed with the seed-phrase accounts (`false`);
- `valoryMultisig`: a Valory multisig address;
- `derivationPath`: a string with the derivation path;
- `CM`: a Community multisig address;
- `providerName`: a network type (see `hardhat.config.js` for the network configurations).

Other values are related to the governance and initial mint. The Gnosis Safe contracts are also provided for convenience. The deployed contract addresses will be added / updated during the scripts run.

The script file name identifies the number of deployment steps taken up to the number in the file name. For example:
- `deploy_02_deployment_factory.js` will complete step 2 from [deployment.md](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/deployment.md) (1 is already complete as the multisig is created beforehand);
- `deploy_08_09_governor_and_roles.js` will complete steps 8 and 9;
- etc.

NOTE: All the scripts MUST be strictly run in the sequential order from smallest to biggest numbers.

Export network-related API keys defined in `hardhat.config.js` file that correspond to the required network.

To run the script, use the following command:
`npx hardhat run scripts/deployment/script_name --network network_type`,
where `script_number_and_name` is a script number and name, i.e. `deploy_02_deployment_factory.js`, `network_type` is a network type corresponding to the `hardhat.config.js` network configuration.

## Validity checks and contract verification
Each script controls the obtained values by checking them against the expected ones. Also, each script has a contract verification procedure.
If a contract is deployed with arguments, these arguments are taken from the corresponding `verify_number_and_name` file, where `number_and_name` corresponds to the deployment script number and name.

## Deployment of supplemental contracts
For deploying supplemental contracts listed in [deployment.md](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/deployment.md),
run the following scripts:
```
npx hardhat run scripts/deployment/deploy_16_wveolas.js --network network_type
npx hardhat run scripts/deployment/deploy_17_governorTwo.js --network network_type
```

Then, after successful deployment of two supplemental contracts, the last script gives the proposal payload necessary to finalize the deployment:
`npx hardhat run scripts/deployment/deploy_18_governor_to_governorTwo.js --network network_type`.

## Deployment of Polygon-Ethereum ERC20 bridging contracts
For deploying ERC20 bridging contracts listed in [deployment.md](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/deployment.md),
run the following scripts:
```
npx hardhat run scripts/deployment/deploy_19_bridged_erc20.js --network mainnet
npx hardhat run scripts/deployment/bridges/polygon/deploy_03_erc20_child_tunnel.js --network polygon
npx hardhat run scripts/deployment/deploy_20_erc20_root_tunnel.js --network mainnet
npx hardhat run scripts/deployment/deploy_21_22_bridged_erc20_change_owners.js --network mainnet
npx hardhat run scripts/deployment/bridges/polygon/deploy_04_set_root_tunnel.js --network polygon
```






