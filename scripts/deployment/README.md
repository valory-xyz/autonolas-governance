# Deployment scripts
This folder contains the scripts to deploy Autonolas governance. These scripts correspond to the steps in the full deployment procedure (as described in [deployment.md](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/deployment.md)).

## Observations
- There are several files with global parameters based on the corresponding network. In order to work with the configuration, please copy `gobals_network.json` file to file the `gobals.json` one, where `network` is the corresponding network. For example: `cp gobals_goerli.json gobals.json`.
- The Valory multisig (Valory) is a Gnosis Safe contract with 3 signers and 2 threshold that already exists.
- The community multisig (CM) of the DAO is a Gnosis Safe contract with 9 signers and 6 threshold that already exists.
- The script to create balances for initial DAO members (`deploy_13.js`) will not be done from the EOA in the mainnet deployment, this will be done from the Valory multisig.
- Please note: if you encounter the `Unknown Error 0x6b0c`, then it is likely because the ledger is not connected or logged in.

## Steps to engage
Make sure the project is installed with the `yarn install` command as described in the main [README](https://github.com/valory-xyz/autonolas-governance/blob/main/README.md)

Create a `globals.json` file in the root folder, or copy it from the file with pre-defined parameters (i.e., `scripts/deployment/globals_goerli.json` for the goerli testnet).

Parameters of the `globals.json` file:
- `contractVerification`: a flag for verifying contracts in deployment scripts (`true`) or skipping it (`false`);
- `useLedger`: a flag whether to use the hardware wallet (`true`) or proceed with the seed-phrase accounts (`false`);
- `valoryMultisig`: a Valory multisig address;
- `derivationPath`: a string with the derivation path;
- `CM`: a Community multisig address;
- `providerName`: a network type (see `hardhat.config.js` for the network configurations).

Other values are related to the governance and initial mint. The Gnosis Safe contracts are also provided for convenience. The deployed contract addresses will be added / updated during the scripts run.

For deployment / testing of the balances creation for initial DAO members (`deploy_13.js`), create the file `claimableBalances.json` in the root folder, or copy it from `scripts/deployment/dummyClaimableBalances.json`.

The script file name identifies the number of deployment steps taken up to the number in the file name. For example:
- `deploy_02.js` will complete steps 1 and 2 from [deployment.md](https://github.com/valory-xyz/autonolas-governance/blob/main/docs/deployment.md) (1 is already complete as the multisig is created beforehand);
- `deploy_04.js` will complete steps 3 and 4;
- etc.

NOTE: All the scripts MUST be strictly run in the sequential order from smallest to biggest numbers.

To run the script, use the following command:
`npx hardhat run scripts/deployment/script_name --network network_type`,
where `script_name` is a script name, i.e. `deploy_02.js`, `network_type` is a network type corresponding to the `hardhat.config.js` network configuration.

## Validity checks and contract verification
Each script controls the obtained values by checking them against the expected ones. Also, each script has a contract verification procedure.
If a contract is deployed with arguments, these arguments are taken from the corresponding `verify_number` file, where `number` corresponds to the deployment script number.







