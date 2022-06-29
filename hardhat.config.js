/*global process*/

require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("@nomiclabs/hardhat-waffle");
require("solidity-coverage");
require("hardhat-gas-reporter");
require("hardhat-contract-sizer");
require("@nomiclabs/hardhat-etherscan");
//require("@nomiclabs/hardhat-ganache");

const accounts = {
    // Generated with bip39
    mnemonic: "velvet deliver grief train result fortune travel voice over subject subject staff nominee bone name",
    accountsBalance: "100000000000000000000000000",
};

const ALCHEMY_API_KEY = process.env.ALCHEMY_API_KEY;
let GOERLI_MNEMONIC = process.env.GOERLI_MNEMONIC;
if (!GOERLI_MNEMONIC) {
    GOERLI_MNEMONIC = accounts.mnemonic;
}
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

module.exports = {
    networks: {
        ganache: {
            url: "http://localhost:8545",
        },
        mainnet: {
            url: "https://eth-mainnet.g.alchemy.com/v2/" + ALCHEMY_API_KEY,
            chainId: 1,
        }
        goerli: {
            url: "https://eth-goerli.alchemyapi.io/v2/" + ALCHEMY_API_KEY,
            chainId: 5,
            accounts: {
                mnemonic: GOERLI_MNEMONIC,
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
            }
        ]
    }
};
