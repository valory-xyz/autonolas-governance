/*global process*/

require("hardhat-contract-sizer");
require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("hardhat-gas-reporter");
require("@nomicfoundation/hardhat-chai-matchers");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("@nomicfoundation/hardhat-toolbox");
//require("hardhat-tracer");

const ALCHEMY_API_KEY_MAINNET = process.env.ALCHEMY_API_KEY_MAINNET;
const ALCHEMY_API_KEY_MATIC = process.env.ALCHEMY_API_KEY_MATIC;
const ALCHEMY_API_KEY_GOERLI = process.env.ALCHEMY_API_KEY_GOERLI;
const ALCHEMY_API_KEY_SEPOLIA = process.env.ALCHEMY_API_KEY_SEPOLIA;
const ALCHEMY_API_KEY_AMOY = process.env.ALCHEMY_API_KEY_AMOY;
let TESTNET_MNEMONIC = process.env.TESTNET_MNEMONIC;

const accounts = {
    mnemonic: TESTNET_MNEMONIC,
    path: "m/44'/60'/0'/0",
    initialIndex: 0,
    count: 20,
};

if (!TESTNET_MNEMONIC) {
    // Generated with bip39
    accounts.mnemonic = "velvet deliver grief train result fortune travel voice over subject subject staff nominee bone name";
    accounts.accountsBalance = "100000000000000000000000000";
}

const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;
const POLYGONSCAN_API_KEY = process.env.POLYGONSCAN_API_KEY;
const GNOSISSCAN_API_KEY = process.env.GNOSISSCAN_API_KEY;
const ARBISCAN_API_KEY = process.env.ARBISCAN_API_KEY;
const OPSCAN_API_KEY = process.env.OPSCAN_API_KEY;
const BASESCAN_API_KEY = process.env.BASESCAN_API_KEY;
const CELOSCAN_API_KEY = process.env.CELOSCAN_API_KEY;

module.exports = {
    networks: {
        local: {
            url: "http://localhost:8545",
        },
        mainnet: {
            url: "https://eth-mainnet.g.alchemy.com/v2/" + ALCHEMY_API_KEY_MAINNET,
            accounts: accounts,
            chainId: 1,
        },
        polygon: {
            url: "https://polygon-mainnet.g.alchemy.com/v2/" + ALCHEMY_API_KEY_MATIC,
            accounts: accounts,
            chainId: 137,
        },
        gnosis: {
            url: "https://rpc.gnosischain.com",
            accounts: accounts,
            chainId: 100,
        },
        arbitrumOne: {
            url: "https://arb1.arbitrum.io/rpc",
            accounts: accounts,
            chainId: 42161,
        },
        optimistic: {
            url: "https://optimism.drpc.org",
            accounts: accounts,
            chainId: 10,
        },
        base: {
            url: "https://mainnet.base.org",
            accounts: accounts,
            chainId: 8453,
        },
        celo: {
            url: "https://forno.celo.org",
            accounts: accounts,
            chainId: 42220,
        },
        goerli: {
            url: "https://eth-goerli.g.alchemy.com/v2/" + ALCHEMY_API_KEY_GOERLI,
            chainId: 5,
            accounts: accounts,
        },
        sepolia: {
            url: "https://eth-sepolia.g.alchemy.com/v2/" + ALCHEMY_API_KEY_SEPOLIA,
            accounts: accounts,
            chainId: 11155111,
        },
        polygonAmoy: {
            url: "https://polygon-amoy.g.alchemy.com/v2/" + ALCHEMY_API_KEY_AMOY,
            accounts: accounts,
        },
        chiado: {
            url: "https://rpc.chiadochain.net",
            accounts: accounts,
        },
        arbitrumSepolia: {
            url: "https://sepolia-rollup.arbitrum.io/rpc",
            accounts: accounts,
            chainId: 421614,
        },
        optimisticSepolia: {
            url: "https://sepolia.optimism.io",
            accounts: accounts,
            chainId: 11155420,
        },
        baseSepolia: {
            url: "https://sepolia.base.org",
            accounts: accounts,
            chainId: 84532,
        },
        celoAlfajores: {
            url: "https://alfajores-forno.celo-testnet.org",
            accounts: accounts,
            chainId: 44787,
        },
        hardhat: {
            allowUnlimitedContractSize: true
        },
    },
    etherscan: {
        customChains: [
            {
                network: "polygonAmoy",
                chainId: 80002,
                urls: {
                    apiURL: "https://api-amoy.polygonscan.com/api",
                    browserURL: "https://amoy.polygonscan.com/"
                }
            },
            {
                network: "chiado",
                chainId: 10200,
                urls: {
                    apiURL: "https://gnosis-chiado.blockscout.com/api",
                    browserURL: "https://gnosis-chiado.blockscout.com/",
                },
            },
            {
                network: "gnosis",
                chainId: 100,
                urls: {
                    apiURL: "https://api.gnosisscan.io/api",
                    browserURL: "https://gnosisscan.io/"
                },
            },
            {
                network: "arbitrumSepolia",
                chainId: 421614,
                urls: {
                    apiURL: "https://api-sepolia.arbiscan.io/api",
                    browserURL: "https://sepolia.arbiscan.io"
                },
            },
            {
                network: "optimistic",
                chainId: 10,
                urls: {
                    apiURL: "https://api-optimistic.etherscan.io/api",
                    browserURL: "https://sepolia-optimistic.etherscan.io"
                },
            },
            {
                network: "optimisticSepolia",
                chainId: 11155420,
                urls: {
                    apiURL: "https://api-sepolia-optimism.etherscan.io/api",
                    browserURL: "https://sepolia-optimistic.etherscan.io"
                },
            },
            {
                network: "base",
                chainId: 8453,
                urls: {
                    apiURL: "https://api.basescan.org/api",
                    browserURL: "https://basescan.org"
                },
            },
            {
                network: "baseSepolia",
                chainId: 84532,
                urls: {
                    apiURL: "https://base-sepolia.blockscout.com/api",
                    browserURL: "https://base-sepolia.blockscout.com/"
                },
            },
            {
                network: "celo",
                chainId: 42220,
                urls: {
                    apiURL: "https://api.celoscan.io/api",
                    browserURL: "https://explorer.celo.org/"
                },
            },
            {
                network: "celoAlfajores",
                chainId: 44787,
                urls: {
                    apiURL: "https://api-alfajores.celoscan.io/api",
                    browserURL: "https://alfajores-blockscout.celo-testnet.org/"
                },
            },
        ],
        apiKey: {
            mainnet: ETHERSCAN_API_KEY,
            polygon: POLYGONSCAN_API_KEY,
            gnosis: GNOSISSCAN_API_KEY,
            arbitrumOne: ARBISCAN_API_KEY,
            optimistic: OPSCAN_API_KEY,
            base: BASESCAN_API_KEY,
            celo: CELOSCAN_API_KEY,
            goerli: ETHERSCAN_API_KEY,
            sepolia: ETHERSCAN_API_KEY,
            polygonAmoy: POLYGONSCAN_API_KEY,
            chiado: GNOSISSCAN_API_KEY,
            arbitrumSepolia: ARBISCAN_API_KEY,
            optimisticSepolia: OPSCAN_API_KEY,
            baseSepolia: OPSCAN_API_KEY,
            celoAlfajores: CELOSCAN_API_KEY
        }
    },
    solidity: {
        compilers: [
            {
                version: "0.8.25",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 1000000,
                    },
                    evmVersion: "cancun"
                },
            }
        ]
    },
    gasReporter: {
        enabled: true
    }
};
