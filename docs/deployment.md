
Pre-deploy steps:
1. Release version of all contracts in `autonolas-governance` with final bytecode.
2. Create and test contract deployFabric with `create2()` and `changeOwner()`, `changeMinter()`.
3. Test the deployment with closest to real environment.

The steps of deploying the contracts in this repository are as follows:

1. EOA creates community multisig (CM) of the DAO with Gnosis Safe, that has ### signers and ### threshold;
2. EOA to deploy deployFabric and get deployAddress of deployFabric;
3. Brutforce salt for vanity address OLAS (deployAddress + bytecode);
4. EOA to deploy OLAS contract via deployFabric (becoming its owner and minter);
5. EOA changes minter on OLAS contract to CM: call `changeMinter(CM)`;
6. EOA changes owner on OLAS contract to CM: call `changeOwner(CM)`.
7. EOA to deploy the Timelock contract with the proposer ("PROPOSER_ROLE"), executor ("EXECUTOR_ROLE"), and canceller ("CANCELLER_ROLE") roles given to the CM (via deployment with `proposers` and `executors` parameters being the CM address);
8. Brutforce salt for vanity address veOLAS (deployAddress + OLAS address + bytecode);
9. EOA to deploy veOLAS contract via deployFabric pointed to OLAS;
10. EOA to deploy GovernorOLAS contract with veOLAS and Timelock addresses as input parameters and other defined governor-related parameters;
11. EOA to give admin ("TIMELOCK_ADMIN_ROLE"), proposer ("PROPOSER_ROLE"), executor ("EXECUTOR_ROLE"), and canceller ("CANCELLER_ROLE") roles to GovernorOLAS from Timelock (in separate transactions via `grantRole()` calls);
12. EOA to deploy buOLAS contract pointed to OLAS.
13. EOA changes owner on buOLAS to CM: call `changeOwner(CM)`;
14. EOA to deploy Sale contract pointed to OLAS, veOLAs and bOLAS;
15. EOA changes the owner on Sale contract to CM: call `changeOwner(CM)`;
16. CM to mint initial OLAS supply for DAO treasury (sent to Timelock), DAO members (sent to Sale contract), Valory (sent to Valory multisig).
17. CM to send transaction to Sale contract (`createBalancesFor()`) to create balances for initial DAO members for them to claim and lock later with veOLAS and buOLAS;
18. CM to transfer its minting rights to Timelock with CM calling `changeMinter(Timelock)`;
19. CM to transfer ownership rights of buOLAS to Timelock calling `changeOwner(Timelock)`;
20. EOA to revoke self admin rights from the Timelock (via `renounceRole()`);
