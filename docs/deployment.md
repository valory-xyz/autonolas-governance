
The steps of deploying the contracts in this repository are as follows:

1. EOA creates community multisig (CM) of the DAO with Gnosis Safe, that has ### signers and ### threshold;
2. EOA to deploy OLAS contract (becoming its owner and minter);
3. EOA changes minter on OLAS contract to CM: call `changeMinter(CM)`; EOA changes owner on OLAS contract to CM with `changeOwner(CM)`.
4. EOA to deploy the Timelock contract with the proposer, executor, and canceller roles given to the CM;
5. EOA to deploy GovernorBravo contract;
6. EOA to deploy veOLAS contract pointed to OLAS;
7. EOA to deploy buOLAS contract.
8. EOA changes the owner on buOLAS to CM: call `changeOwner(CM)`;
9. EOA to deploy Sale contract pointed to OLAS, veOLAs and buOLAS;
10. EOA changes the owner on Sale contract to CM: call `changeOwner(CM)`;
11. CM to mint initial OLAS supply for DAO treasury (sent to Timelock), DAO members (sent to Sale contract), Valory (sent to Valory multisig).
12. CM to transfer its minting rights to Timelock with CM calling `changeMinter(Timelock)`;
13. CM to send transaction to Sale contract (`createBalancesFor()`) to create balances for initial DAO members for them to claim and lock later with veOLAS and buOLAS;
14. CM to transfer ownership rights of buOLAS to Timelock calling `changeOwner(Timelock)`;
15. EOA to revoke self admin rights from the Timelock;
