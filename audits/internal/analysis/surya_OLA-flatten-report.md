## Sūrya's Description Report

### Files Description Table


|  File Name  |  SHA-1 Hash  |
|-------------|--------------|
| OLA-flatten.sol | d0f0450c7292111f6e2cb429c20a9060f173df9e |


### Contracts Description Table


|  Contract  |         Type        |       Bases      |                  |                 |
|:----------:|:-------------------:|:----------------:|:----------------:|:---------------:|
|     └      |  **Function Name**  |  **Visibility**  |  **Mutability**  |  **Modifiers**  |
||||||
| **ERC20** | Implementation |  |||
| └ | <Constructor> | Public ❗️ | 🛑  |NO❗️ |
| └ | approve | Public ❗️ | 🛑  |NO❗️ |
| └ | transfer | Public ❗️ | 🛑  |NO❗️ |
| └ | transferFrom | Public ❗️ | 🛑  |NO❗️ |
| └ | permit | Public ❗️ | 🛑  |NO❗️ |
| └ | DOMAIN_SEPARATOR | Public ❗️ |   |NO❗️ |
| └ | computeDomainSeparator | Internal 🔒 |   | |
| └ | _mint | Internal 🔒 | 🛑  | |
| └ | _burn | Internal 🔒 | 🛑  | |
||||||
| **OLA** | Implementation | ERC20 |||
| └ | <Constructor> | Public ❗️ | 🛑  | ERC20 |
| └ | changeOwner | External ❗️ | 🛑  |NO❗️ |
| └ | changeMinter | External ❗️ | 🛑  |NO❗️ |
| └ | mint | External ❗️ | 🛑  |NO❗️ |
| └ | inflationControl | Public ❗️ |   |NO❗️ |
| └ | inflationRemainder | Public ❗️ |   |NO❗️ |
| └ | burn | External ❗️ | 🛑  |NO❗️ |
| └ | decreaseAllowance | External ❗️ | 🛑  |NO❗️ |
| └ | increaseAllowance | External ❗️ | 🛑  |NO❗️ |


### Legend

|  Symbol  |  Meaning  |
|:--------:|-----------|
|    🛑    | Function can modify state |
|    💵    | Function is payable |
