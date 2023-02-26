Pre-deploy steps:
1. Release version of all contracts in `autonolas-governance` with the final bytecode.
2. Create and test contract DeploymentFactory with `create2()` for OLAS and veOLAS, and `changeOwner()`.
3. Test the deployment flow with closest to real environment.

The steps of deploying the contracts in this repository are as follows:

1. EOA creates community multisig (CM) of the DAO with Gnosis Safe, that has 9 signers and 6 threshold;
2. EOA to deploy DeploymentFactory and get the deploymentAddress of DeploymentFactory;
3. Brute force salt for vanity address OLAS (deploymentAddress + bytecode);
4. EOA to deploy OLAS contract via DeploymentFactory (with EOA becoming its owner and minter);
5. EOA to deploy the Timelock contract with the proposer ("PROPOSER_ROLE"), executor ("EXECUTOR_ROLE"), and canceller ("CANCELLER_ROLE") roles given to the CM (via deployment with `proposers` and `executors` parameters being the CM address);
6. Brute force salt for vanity address veOLAS (deploymentAddress + OLAS address + bytecode);
7. EOA to deploy veOLAS contract via DeploymentFactory pointed to OLAS;
8. EOA to deploy GovernorOLAS contract with wveOLAS and Timelock addresses as input parameters and other defined governor-related parameters;
9. EOA to give admin ("TIMELOCK_ADMIN_ROLE"), proposer ("PROPOSER_ROLE"), executor ("EXECUTOR_ROLE"), and canceller ("CANCELLER_ROLE") roles to GovernorOLAS from Timelock (in separate transactions via `grantRole()` calls);
10. EOA to deploy buOLAS contract pointed to OLAS;
11. EOA to deploy wveOLAS contract pointed to veOLAS;
12. EOA to mint initial OLAS supply for DAO treasury (sent to Timelock), DAO members (sent to Sale contract), Valory (sent to Valory multisig);
13. EOA to transfer its minting and its ownership rights of OLAS to Timelock with EOA calling `changeMinter(Timelock)` and `changeOwner(Timelock)`;
14. EOA to transfer ownership rights of buOLAS to Timelock calling `changeOwner(Timelock)`;
15. EOA to revoke self admin rights from the Timelock (via `renounceRole()`);
16. EOA to revoke self ownership rights from DeploymentFactory to Null Address (via `changeOwner(0x000000000000000000000000000000000000dEaD)`);
17. EOA to deploy new wGovernorOLAS contract with wveOLAS and Timelock addresses as input parameters and other defined governor-related parameters;
18. Timelock to revoke admin ("TIMELOCK_ADMIN_ROLE"), proposer ("PROPOSER_ROLE"), executor ("EXECUTOR_ROLE"), and canceller ("CANCELLER_ROLE") roles from GovernorOLAS, give admin ("TIMELOCK_ADMIN_ROLE"), proposer ("PROPOSER_ROLE"), executor ("EXECUTOR_ROLE"), and canceller ("CANCELLER_ROLE") roles to wGovernorOLAS (via voting).