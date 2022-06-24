
Pre-deploy steps:
1. Release version of all contracts in `autonolas-governance` with the final bytecode.
2. Create and test contract DeploymentFactory with `create2()` for OLAS and veOLAS, and `changeOwner()`.
3. Test the deployment flow with closest to real environment.

The steps of deploying the contracts in this repository are as follows:

0. EOA to create Valory multisig, that has 3 signers and 2 threshold;
1. EOA creates community multisig (CM) of the DAO with Gnosis Safe, that has 9 signers and 6 threshold;
2. EOA to deploy DeploymentFactory and get the deploymentAddress of DeploymentFactory;
3. Brute force salt for vanity address OLAS (deploymentAddress + bytecode);
4. EOA to deploy OLAS contract via DeploymentFactory (with EOA becoming its owner);
5. EOA changes owner and minter on OLAS contract to CM: call `changeMinter(CM)` and `changeOwner(CM)`;
6. EOA to deploy the Timelock contract with the proposer ("PROPOSER_ROLE"), executor ("EXECUTOR_ROLE"), and canceller ("CANCELLER_ROLE") roles given to the CM (via deployment with `proposers` and `executors` parameters being the CM address);
7. Brute force salt for vanity address veOLAS (deploymentAddress + OLAS address + bytecode);
8. EOA to deploy veOLAS contract via DeploymentFactory pointed to OLAS;
9. EOA to deploy GovernorOLAS contract with veOLAS and Timelock addresses as input parameters and other defined governor-related parameters;
10. EOA to give admin ("TIMELOCK_ADMIN_ROLE"), proposer ("PROPOSER_ROLE"), executor ("EXECUTOR_ROLE"), and canceller ("CANCELLER_ROLE") roles to GovernorOLAS from Timelock (in separate transactions via `grantRole()` calls);
11. EOA to deploy buOLAS contract pointed to OLAS;
12. EOA changes the ownership of buOLAS contract to CM: call `changeOwner(CM)`;
13. EOA to deploy Sale contract pointed to OLAS, veOLAs and bOLAS;
14. EOA changes the ownership of Sale contract to CM: call `changeOwner(CM)`;
15. CM to mint initial OLAS supply for DAO treasury (sent to Timelock), DAO members (sent to Sale contract), Valory (sent to Valory multisig);
16. CM to send transaction to Sale contract (`createBalancesFor()`) to create balances for initial DAO members for them to claim and lock later with veOLAS and buOLAS;
17. CM to transfer its minting and its ownership rights to Timelock with CM calling `changeMinter(Timelock)` and `changeOwner(Timelock)`;
18. CM to transfer ownership rights of buOLAS to Timelock calling `changeOwner(Timelock)`;
19. CM to transfer ownership rights of Sale to Valory multisig calling `changeOwner(ValoryMultisig)`;
20. EOA to revoke self admin rights from the Timelock (via `renounceRole()`);
21. EOA to revoke self ownership rights from DeploymentFactory to Null Address (via `changeOwner(0x000000000000000000000000000000000000dEaD)`).