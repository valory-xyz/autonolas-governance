
The steps of deploying the contracts in this repository are as follows:

1. EOA to deploy community multisig (CM) of the DAO and add signers;
2. EOA to deploy OLAS contract with the owner set to CM;
3. EOA to deploy the Timelock contract with the proposer, executor, and canceller roles given to the CM;
4. CM to send a transaction to OLAS contract to mint initial OLAS supply.
5. EOA to deploy veOLAS contract pointed to OLAS;
6. EOA to deploy buOLAS contract pointed to OLAS with the owner set to CM;
7. EOA to deploy Sale contract pointed to OLAS, veOLAs and buOLAS with the owner set to CM;
8. CM to send DAO members' allocation to Sale contract;
9. CM to revoke its minting rights from OLA; CM to transfer ownership rights of OLA to Timelock;
10. CM to send transaction to Sale contract to create locks for initial DAO members;
11. CM to transfer ownership rights of buOLAS to Timelock;
12. EOA to revoke self admin rights from the Timelock;
