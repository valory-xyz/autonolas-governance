## Sūrya's Description Report

### Files Description Table


|  File Name  |  SHA-1 Hash  |
|-------------|--------------|
| Timelock-flatten.sol | 6f0ba0627054b8cb107830d8db1129630cd5391b |


### Contracts Description Table


|  Contract  |         Type        |       Bases      |                  |                 |
|:----------:|:-------------------:|:----------------:|:----------------:|:---------------:|
|     └      |  **Function Name**  |  **Visibility**  |  **Mutability**  |  **Modifiers**  |
||||||
| **IAccessControl** | Interface |  |||
| └ | hasRole | External ❗️ |   |NO❗️ |
| └ | getRoleAdmin | External ❗️ |   |NO❗️ |
| └ | grantRole | External ❗️ | 🛑  |NO❗️ |
| └ | revokeRole | External ❗️ | 🛑  |NO❗️ |
| └ | renounceRole | External ❗️ | 🛑  |NO❗️ |
||||||
| **Context** | Implementation |  |||
| └ | _msgSender | Internal 🔒 |   | |
| └ | _msgData | Internal 🔒 |   | |
||||||
| **Strings** | Library |  |||
| └ | toString | Internal 🔒 |   | |
| └ | toHexString | Internal 🔒 |   | |
| └ | toHexString | Internal 🔒 |   | |
||||||
| **IERC165** | Interface |  |||
| └ | supportsInterface | External ❗️ |   |NO❗️ |
||||||
| **ERC165** | Implementation | IERC165 |||
| └ | supportsInterface | Public ❗️ |   |NO❗️ |
||||||
| **AccessControl** | Implementation | Context, IAccessControl, ERC165 |||
| └ | supportsInterface | Public ❗️ |   |NO❗️ |
| └ | hasRole | Public ❗️ |   |NO❗️ |
| └ | _checkRole | Internal 🔒 |   | |
| └ | _checkRole | Internal 🔒 |   | |
| └ | getRoleAdmin | Public ❗️ |   |NO❗️ |
| └ | grantRole | Public ❗️ | 🛑  | onlyRole |
| └ | revokeRole | Public ❗️ | 🛑  | onlyRole |
| └ | renounceRole | Public ❗️ | 🛑  |NO❗️ |
| └ | _setupRole | Internal 🔒 | 🛑  | |
| └ | _setRoleAdmin | Internal 🔒 | 🛑  | |
| └ | _grantRole | Internal 🔒 | 🛑  | |
| └ | _revokeRole | Internal 🔒 | 🛑  | |
||||||
| **IERC721Receiver** | Interface |  |||
| └ | onERC721Received | External ❗️ | 🛑  |NO❗️ |
||||||
| **IERC1155Receiver** | Interface | IERC165 |||
| └ | onERC1155Received | External ❗️ | 🛑  |NO❗️ |
| └ | onERC1155BatchReceived | External ❗️ | 🛑  |NO❗️ |
||||||
| **TimelockController** | Implementation | AccessControl, IERC721Receiver, IERC1155Receiver |||
| └ | <Constructor> | Public ❗️ | 🛑  |NO❗️ |
| └ | <Receive Ether> | External ❗️ |  💵 |NO❗️ |
| └ | supportsInterface | Public ❗️ |   |NO❗️ |
| └ | isOperation | Public ❗️ |   |NO❗️ |
| └ | isOperationPending | Public ❗️ |   |NO❗️ |
| └ | isOperationReady | Public ❗️ |   |NO❗️ |
| └ | isOperationDone | Public ❗️ |   |NO❗️ |
| └ | getTimestamp | Public ❗️ |   |NO❗️ |
| └ | getMinDelay | Public ❗️ |   |NO❗️ |
| └ | hashOperation | Public ❗️ |   |NO❗️ |
| └ | hashOperationBatch | Public ❗️ |   |NO❗️ |
| └ | schedule | Public ❗️ | 🛑  | onlyRole |
| └ | scheduleBatch | Public ❗️ | 🛑  | onlyRole |
| └ | _schedule | Private 🔐 | 🛑  | |
| └ | cancel | Public ❗️ | 🛑  | onlyRole |
| └ | execute | Public ❗️ |  💵 | onlyRoleOrOpenRole |
| └ | executeBatch | Public ❗️ |  💵 | onlyRoleOrOpenRole |
| └ | _beforeCall | Private 🔐 |   | |
| └ | _afterCall | Private 🔐 | 🛑  | |
| └ | _call | Private 🔐 | 🛑  | |
| └ | updateDelay | External ❗️ | 🛑  |NO❗️ |
| └ | onERC721Received | Public ❗️ | 🛑  |NO❗️ |
| └ | onERC1155Received | Public ❗️ | 🛑  |NO❗️ |
| └ | onERC1155BatchReceived | Public ❗️ | 🛑  |NO❗️ |
||||||
| **Timelock** | Implementation | TimelockController |||
| └ | <Constructor> | Public ❗️ | 🛑  | TimelockController |


### Legend

|  Symbol  |  Meaning  |
|:--------:|-----------|
|    🛑    | Function can modify state |
|    💵    | Function is payable |
