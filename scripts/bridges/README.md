# Bridge-related deployment scripts
This process is the same as described in the original deployment procedure: [deployment](https://github.com/valory-xyz/autonolas-governance/blob/main/scripts/deployment).

Create a `globals.json` file in the root folder, or copy it from the file with pre-defined parameters (i.e., `scripts/bridges/globals_polygon_mumbai.json` for the mumbai testnet).

Parameters of the `globals.json` file:
- `contractVerification`: flag for verifying contracts in deployment scripts (`true`) or skipping it (`false`);
- `useLedger`: flag whether to use the hardware wallet (`true`) or proceed with the seed-phrase accounts (`false`);
- `derivationPath`: string with the derivation path;
- `fxChildAddress`: Fx Child contract address serving as a system processor of inbound calls across the bridge;
- `timelockAddress`: Timelock address on the root L1 network;

The script file name identifies the number of deployment steps taken up to the number in the file name.

To run the script, use the following command:
`npx hardhat run scripts/deployment/script_name --network network_type`,
where `script_number_and_name` is a script number and name, i.e. `deploy_01_governor_tunnel.js`, `network_type` is a network type corresponding to the `hardhat.config.js` network configuration.

## Validity checks and contract verification
Each script controls the obtained values by checking them against the expected ones. Also, each script has a contract verification procedure.
If a contract is deployed with arguments, these arguments are taken from the corresponding `verify_number_and_name` file, where `number_and_name` corresponds to the deployment script number and name.

## Data packing for cross-bridge transactions
In order to correctly pack the data and supply it to the Timelock such that it is correctly processed across the bridge,
use the following script: [cross-bridge data packing](https://github.com/valory-xyz/autonolas-governance/blob/main/scripts/bridges/pack-data.js).






