/*global process*/

require("hardhat-contract-sizer");
require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("hardhat-gas-reporter");
require("hardhat-tracer");
require("@nomicfoundation/hardhat-chai-matchers");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("@nomicfoundation/hardhat-toolbox");

const accounts = {
    mnemonic: "test test test test test test test test test test test junk",
    accountsBalance: "100000000000000000000000000",
};

const ALCHEMY_API_KEY_MAINNET = process.env.ALCHEMY_API_KEY_MAINNET;
const ALCHEMY_API_KEY_MATIC = process.env.ALCHEMY_API_KEY_MATIC;
const ALCHEMY_API_KEY_GOERLI = process.env.ALCHEMY_API_KEY_GOERLI;
const ALCHEMY_API_KEY_MUMBAI = process.env.ALCHEMY_API_KEY_MUMBAI;
let TESTNET_MNEMONIC = process.env.TESTNET_MNEMONIC;
if (!TESTNET_MNEMONIC) {
    TESTNET_MNEMONIC = accounts.mnemonic;
}
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

module.exports = {
    networks: {
        local: {
            url: "http://localhost:8545",
        },
        mainnet: {
            url: "https://eth-mainnet.g.alchemy.com/v2/" + ALCHEMY_API_KEY_MAINNET,
            chainId: 1,
        },
        matic: {
            url: "https://polygon-mainnet.g.alchemy.com/v2/" + ALCHEMY_API_KEY_MATIC,
            chainId: 137,
        },
        goerli: {
            url: "https://eth-goerli.g.alchemy.com/v2/" + ALCHEMY_API_KEY_GOERLI,
            chainId: 5,
            accounts: {
                mnemonic: TESTNET_MNEMONIC,
                path: "m/44'/60'/0'/0",
                initialIndex: 0,
                count: 20,
                passphrase: "",
            },
        },
        mumbai: {
            url: "https://polygon-mumbai.g.alchemy.com/v2/" + ALCHEMY_API_KEY_MUMBAI,
            accounts: {
                mnemonic: TESTNET_MNEMONIC,
                path: "m/44'/60'/0'/0",
                initialIndex: 0,
                count: 20,
                passphrase: "",
            },
        },
        hardhat: {
            allowUnlimitedContractSize: true,
            accounts
        },
    },
    etherscan: {
        apiKey: ETHERSCAN_API_KEY
    },
    solidity: {
        compilers: [
            {
                version: "0.8.15",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 1000000,
                    },
                },
            },
            {
                version: "0.8.19",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 1000000,
                    },
                },
            }
        ]
    },
    gasReporter: {
        enabled: true
    }
};
