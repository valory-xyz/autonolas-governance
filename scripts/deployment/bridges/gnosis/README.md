# Bridge-related deployment scripts
This process is the same as described in the original deployment procedure: [deployment](https://github.com/valory-xyz/autonolas-governance/blob/main/scripts/deployment).

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

Create a `globals.json` file in the root folder, or copy it from the file with pre-defined parameters (i.e., `scripts/deployment/bridges/gnosis/globals_gnosis_chiado.json` for the chiado testnet).

Parameters of the `globals.json` file:
- `contractVerification`: flag for verifying contracts in deployment scripts (`true`) or skipping it (`false`);
- `useLedger`: flag whether to use the hardware wallet (`true`) or proceed with the seed-phrase accounts (`false`);
- `derivationPath`: string with the derivation path;
- `providerName`: a network type (see `hardhat.config.js` for the network configurations);
- `gasPriceInGwei`: gas price in Gwei;
- `AMBContractProxyHomeAddress`: (Gnosis) AMB Contract Proxy Homeaddress serving as a system processor of inbound calls across the bridge;
- `timelockAddress`: Timelock address on the root L1 network;

The script file name identifies the number of deployment steps taken up to the number in the file name.

Export network-related API keys defined in `hardhat.config.js` file that correspond to the required network.

To run the script, use the following command:
`npx hardhat run scripts/deployment/bridges/script_name --network network_type`,
where `script_number_and_name` is a script number and name, i.e. `deploy_01_home_mediator.js`, `network_type` is a network type corresponding to the `hardhat.config.js` network configuration.

## Validity checks and contract verification
Each script controls the obtained values by checking them against the expected ones. Also, each script has a contract verification procedure.
If a contract is deployed with arguments, these arguments are taken from the corresponding `verify_number_and_name` file, where `number_and_name` corresponds to the deployment script number and name.

## Data packing for cross-bridge transactions
In order to correctly pack the data and supply it to the Timelock such that it is correctly processed across the bridge,
use the following script: [cross-bridge data packing](https://github.com/valory-xyz/autonolas-governance/blob/main/scripts/deployment/bridges/pack-data.js).







