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
    mnemonic: "velvet deliver grief train result fortune travel voice over subject subject staff nominee bone name",
    accountsBalance: "100000000000000000000000000",
};

const ALCHEMY_API_KEY = process.env.ALCHEMY_API_KEY;
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

module.exports = {
    networks: {
        ganache: {
            url: "http://localhost:8545",
        },
        goerli: {
            url: "https://eth-goerli.alchemyapi.io/v2/" + ALCHEMY_API_KEY,
            chainId: 5,
            accounts: {
                mnemonic: "hair ugly glass focus game announce tape stairs abandon rack earn script",
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
                        runs: 1000,
                    },
                },
            }
        ]
    }
};
