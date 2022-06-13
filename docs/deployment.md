
Pre-deploy steps:
1. Release version of all contracts in `autonolas-governance` with final bytecode.
2. Create and test contract deployFactory with `create2()`.
3. Test the deployment with closest to real environment.

The steps of deploying the contracts in this repository are as follows:

1. EOA creates community multisig (CM) of the DAO with Gnosis Safe, that has ### signers and ### threshold;
2. EOA to deploy deployFactory and get deployAddress of deployFactory;
3. Brutforce salt for vanity address OLAS (deployAddress + bytecode);
4. EOA to deploy OLAS contract via deployFactory (with EOA becoming its owner);
5. EOA changes owner and minter on OLAS contract to CM: call `changeMinter(CM)` and `changeOwner(CM)`;
6. EOA to deploy the Timelock contract with the proposer ("PROPOSER_ROLE"), executor ("EXECUTOR_ROLE"), and canceller ("CANCELLER_ROLE") roles given to the CM (via deployment with `proposers` and `executors` parameters being the CM address);
7. Brutforce salt for vanity address veOLAS (deployAddress + OLAS address + bytecode);
8. EOA to deploy veOLAS contract via deployFactory pointed to OLAS;
9. EOA to deploy GovernorOLAS contract with veOLAS and Timelock addresses as input parameters and other defined governor-related parameters;
10. EOA to give admin ("TIMELOCK_ADMIN_ROLE"), proposer ("PROPOSER_ROLE"), executor ("EXECUTOR_ROLE"), and canceller ("CANCELLER_ROLE") roles to GovernorOLAS from Timelock (in separate transactions via `grantRole()` calls);
11. EOA to deploy buOLAS contract pointed to OLAS;
12. EOA changes owner on buOLAS to CM: call `changeOwner(CM)`;
13. EOA to deploy Sale contract pointed to OLAS, veOLAs and bOLAS;
14. EOA changes the owner on Sale contract to CM: call `changeOwner(CM)`;
15. CM to mint initial OLAS supply for DAO treasury (sent to Timelock), DAO members (sent to Sale contract), Valory (sent to Valory multisig);
16. CM to send transaction to Sale contract (`createBalancesFor()`) to create balances for initial DAO members for them to claim and lock later with veOLAS and buOLAS;
17. CM to transfer its minting rights to Timelock with CM calling `changeMinter(Timelock)`;
18. CM to transfer ownership rights of buOLAS to Timelock calling `changeOwner(Timelock)`;
19. EOA to revoke self admin rights from the Timelock (via `renounceRole()`);
