require("hardhat-deploy");
require("@nomiclabs/hardhat-waffle");
require("solidity-coverage");
require("hardhat-gas-reporter");
require("hardhat-contract-sizer");
//require("@nomiclabs/hardhat-ganache");

const accounts = {
    mnemonic: "test test test test test test test test test test test junk",
    accountsBalance: "100000000000000000000000000",
};

module.exports = {
    networks: {
        ganache: {
            url: "http://localhost:8545",
        },
        hardhat: {
            allowUnlimitedContractSize: true,
            accounts
        },
    },
    solidity: {
        compilers: [
            {
                version: "0.8.14",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 1000,
                    },
                },
            }
        ]
    }
};
