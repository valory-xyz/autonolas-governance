## Sūrya's Description Report

### Files Description Table


|  File Name  |  SHA-1 Hash  |
|-------------|--------------|
| VotingEscrow-flatten.sol | 3dbd75b9be131bf587a7486390fd6faa9056937e |


### Contracts Description Table


|  Contract  |         Type        |       Bases      |                  |                 |
|:----------:|:-------------------:|:----------------:|:----------------:|:---------------:|
|     └      |  **Function Name**  |  **Visibility**  |  **Mutability**  |  **Modifiers**  |
||||||
| **IVotes** | Interface |  |||
| └ | getVotes | External ❗️ |   |NO❗️ |
| └ | getPastVotes | External ❗️ |   |NO❗️ |
| └ | getPastTotalSupply | External ❗️ |   |NO❗️ |
| └ | delegates | External ❗️ |   |NO❗️ |
| └ | delegate | External ❗️ | 🛑  |NO❗️ |
| └ | delegateBySig | External ❗️ | 🛑  |NO❗️ |
||||||
| **IERC20** | Interface |  |||
| └ | totalSupply | External ❗️ |   |NO❗️ |
| └ | balanceOf | External ❗️ |   |NO❗️ |
| └ | transfer | External ❗️ | 🛑  |NO❗️ |
| └ | allowance | External ❗️ |   |NO❗️ |
| └ | approve | External ❗️ | 🛑  |NO❗️ |
| └ | transferFrom | External ❗️ | 🛑  |NO❗️ |
||||||
| **IERC165** | Interface |  |||
| └ | supportsInterface | External ❗️ |   |NO❗️ |
||||||
| **IErrors** | Interface |  |||
||||||
| **VotingEscrow** | Implementation | IErrors, IVotes, IERC20, IERC165 |||
| └ | <Constructor> | Public ❗️ | 🛑  |NO❗️ |
| └ | getLastUserPoint | External ❗️ |   |NO❗️ |
| └ | getNumUserPoints | External ❗️ |   |NO❗️ |
| └ | getUserPoint | External ❗️ |   |NO❗️ |
| └ | _checkpoint | Internal 🔒 | 🛑  | |
| └ | checkpoint | External ❗️ | 🛑  |NO❗️ |
| └ | _depositFor | Internal 🔒 | 🛑  | |
| └ | depositFor | External ❗️ | 🛑  |NO❗️ |
| └ | createLock | External ❗️ | 🛑  |NO❗️ |
| └ | createLockFor | External ❗️ | 🛑  |NO❗️ |
| └ | _createLockFor | Private 🔐 | 🛑  | |
| └ | increaseAmount | External ❗️ | 🛑  |NO❗️ |
| └ | increaseUnlockTime | External ❗️ | 🛑  |NO❗️ |
| └ | withdraw | External ❗️ | 🛑  |NO❗️ |
| └ | _findPointByBlock | Internal 🔒 |   | |
| └ | _balanceOfLocked | Internal 🔒 |   | |
| └ | balanceOf | Public ❗️ |   |NO❗️ |
| └ | lockedEnd | External ❗️ |   |NO❗️ |
| └ | balanceOfAt | External ❗️ |   |NO❗️ |
| └ | getVotes | Public ❗️ |   |NO❗️ |
| └ | _getBlockTime | Internal 🔒 |   | |
| └ | getPastVotes | Public ❗️ |   |NO❗️ |
| └ | _supplyLockedAt | Internal 🔒 |   | |
| └ | totalSupply | Public ❗️ |   |NO❗️ |
| └ | totalSupplyAt | External ❗️ |   |NO❗️ |
| └ | totalSupplyLockedAtT | Public ❗️ |   |NO❗️ |
| └ | totalSupplyLocked | Public ❗️ |   |NO❗️ |
| └ | getPastTotalSupply | Public ❗️ |   |NO❗️ |
| └ | supportsInterface | Public ❗️ |   |NO❗️ |
| └ | transfer | External ❗️ | 🛑  |NO❗️ |
| └ | approve | External ❗️ | 🛑  |NO❗️ |
| └ | transferFrom | External ❗️ | 🛑  |NO❗️ |
| └ | allowance | External ❗️ |   |NO❗️ |
| └ | delegates | External ❗️ |   |NO❗️ |
| └ | delegate | External ❗️ | 🛑  |NO❗️ |
| └ | delegateBySig | External ❗️ | 🛑  |NO❗️ |


### Legend

|  Symbol  |  Meaning  |
|:--------:|-----------|
|    🛑    | Function can modify state |
|    💵    | Function is payable |
