/*global process*/

const { ethers } = require("ethers");
const { expect } = require("chai");
const fs = require("fs");

const verifyRepo = true;
const verifySetup = true;

// Custom expect that is wrapped into try / catch block
function customExpect(arg1, arg2, log) {
    try {
        expect(arg1).to.equal(arg2);
    } catch (error) {
        console.log(log);
        if (error.status) {
            console.error(error.status);
            console.log("\n");
        } else {
            console.error(error);
            console.log("\n");
        }
    }
}

// Custom expect for contain clause that is wrapped into try / catch block
function customExpectContain(arg1, arg2, log) {
    try {
        expect(arg1).contain(arg2);
    } catch (error) {
        console.log(log);
        if (error.status) {
            console.error(error.status);
            console.log("\n");
        } else {
            console.error(error);
            console.log("\n");
        }
    }
}

// Check the bytecode
async function checkBytecode(provider, configContracts, contractName, log) {
    // Get the contract number from the set of configuration contracts
    for (let i = 0; i < configContracts.length; i++) {
        if (configContracts[i]["name"] === contractName) {
            // Get the contract instance
            const contractFromJSON = fs.readFileSync(configContracts[i]["artifact"], "utf8");
            const parsedFile = JSON.parse(contractFromJSON);
            const bytecode = parsedFile["deployedBytecode"];
            const onChainCreationCode = await provider.getCode(configContracts[i]["address"]);

            // Compare last 8-th part of deployed bytecode bytes (wveOLAS can't manage more)
            // We cannot compare the full one since the repo deployed bytecode does not contain immutable variable info
            const slicePart = -bytecode.length / 8;
            customExpectContain(onChainCreationCode, bytecode.slice(slicePart),
                log + ", address: " + configContracts[i]["address"] + ", failed bytecode comparison");
            return;
        }
    }
}

// Find the contract name from the configuration data
async function findContractInstance(provider, configContracts, contractName) {
    // Get the contract number from the set of configuration contracts
    for (let i = 0; i < configContracts.length; i++) {
        if (configContracts[i]["name"] === contractName) {
            // Get the contract instance
            const contractFromJSON = fs.readFileSync(configContracts[i]["artifact"], "utf8");
            const parsedFile = JSON.parse(contractFromJSON);
            const abi = parsedFile["abi"];
            const contractInstance = new ethers.Contract(configContracts[i]["address"], abi, provider);
            return contractInstance;
        }
    }
}

// Check OLAS: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkOLAS(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const olas = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + olas.address;
    // Check owner
    const owner = await olas.owner();
    customExpect(owner, globalsInstance["timelockAddress"], log + ", function: owner()");

    // Check minter
    const manager = await olas.minter();
    customExpect(manager, globalsInstance["treasuryAddress"], log + ", function: minter()");
}

// Check Timelock: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkTimelock(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const timelock = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + timelock.address;
    // Check roles
    const adminRole = ethers.utils.id("TIMELOCK_ADMIN_ROLE");
    const proposerRole = ethers.utils.id("PROPOSER_ROLE");
    const executorRole = ethers.utils.id("EXECUTOR_ROLE");
    const cancellerRole = ethers.utils.id("CANCELLER_ROLE");

    // All must be true for the governor
    let res = await timelock.hasRole(adminRole, globalsInstance["governorTwoAddress"]);
    customExpect(res, true, log + ", function: hasRole(adminRole)");
    res = await timelock.hasRole(proposerRole, globalsInstance["governorTwoAddress"]);
    customExpect(res, true, log + ", function: hasRole(proposerRole)");
    res = await timelock.hasRole(executorRole, globalsInstance["governorTwoAddress"]);
    customExpect(res, true, log + ", function: hasRole(executorRole)");
    res = await timelock.hasRole(cancellerRole, globalsInstance["governorTwoAddress"]);
    customExpect(res, true, log + ", function: hasRole(cancellerRole)");

    // CM must have all the roles except for the admin one
    res = await timelock.hasRole(adminRole, globalsInstance["CM"]);
    customExpect(res, false, log + ", function: hasRole(adminRole)");
    res = await timelock.hasRole(proposerRole, globalsInstance["CM"]);
    customExpect(res, true, log + ", function: hasRole(proposerRole)");
    res = await timelock.hasRole(executorRole, globalsInstance["CM"]);
    customExpect(res, true, log + ", function: hasRole(executorRole)");
    res = await timelock.hasRole(cancellerRole, globalsInstance["CM"]);
    customExpect(res, false, log + ", function: hasRole(cancellerRole)");

    // Timelock has the admin role as well
    res = await timelock.hasRole(adminRole, globalsInstance["timelockAddress"]);
    customExpect(res, true, log + ", function: hasRole(adminRole)");

    // Check timelock min delay
    res = await timelock.getMinDelay();
    customExpect(res.toString(), globalsInstance["timelockMinDelay"], log + ", function: hasRole(adminRole)");
}

// Check veOLAS: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkVEOLAS(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const veOLAS = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + veOLAS.address;
    // Check current token
    const token = await veOLAS.token();
    customExpect(token, globalsInstance["olasAddress"], log + ", function: token()");

}

// Check buOLAS: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkBUOLAS(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const buOLAS = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + buOLAS.address;
    // Check current token
    const token = await buOLAS.token();
    customExpect(token, globalsInstance["olasAddress"], log + ", function: token()");

    // Check owner
    const owner = await buOLAS.owner();
    customExpect(owner, globalsInstance["timelockAddress"], log + ", function: owner()");
}

// Check wveOLAS: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkWrappedVEOLAS(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const wveOLAS = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + wveOLAS.address;
    // Check current token
    const token = await wveOLAS.token();
    customExpect(token, globalsInstance["olasAddress"], log + ", function: token()");
    
    // Check ve
    const ve = await wveOLAS.ve();
    customExpect(ve, globalsInstance["veOLASAddress"], log + ", function: ve()");
}

// Check GolvernorOLAS: chain Id, provider, parsed globals, mainnet globals, configuration contracts, contract name
async function checkGovernorOLAS(chainId, provider, globalsInstance, globalsMainnet, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const governor = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + governor.address;
    // Check current token
    const token = await governor.token();
    customExpect(token, globalsInstance["wveOLASAddress"], log + ", function: token()");

    // Check timelock
    const timelock = await governor.timelock();
    customExpect(timelock, globalsInstance["timelockAddress"], log + ", function: timelock()");

    // Check version
    const version = await governor.version();
    customExpect(version, "1", log + ", function: version()");

    // Value below need to be in sync with mainnet
    // Check quorumNumerator
    const quorumNumerator = await governor["quorumNumerator()"]();
    customExpect(quorumNumerator.toString(), globalsMainnet["quorum"], log + ", function: quorumNumerator()");

    // Check votingDelay
    const vDelay = await governor.votingDelay();
    customExpect(vDelay.toString(), globalsMainnet["initialVotingDelay"], log + ", function: votingDelay()");

    // Check quorumNumerator
    const vPeriod = await governor.votingPeriod();
    customExpect(vPeriod.toString(), globalsMainnet["initialVotingPeriod"], log + ", function: votingPeriod()");
}

// Check GuardCM: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkGuardCM(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const guard = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + guard.address;
    // Check governor
    const governor = await guard.governor();
    customExpect(governor, globalsInstance["governorTwoAddress"], log + ", function: governor()");

    // Check timelock to be the owner
    const timelock = await guard.owner();
    customExpect(timelock, globalsInstance["timelockAddress"], log + ", function: owner()");

    // Check multisig to be the CM
    const multisig = await guard.multisig();
    customExpect(multisig, globalsInstance["CM"], log + ", function: multisig()");
}

// Check bridgedERC20: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkBridgedERC20(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const bridgedERC20 = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + bridgedERC20.address;
    // Check the owner
    const owner = await bridgedERC20.owner();
    customExpect(owner, globalsInstance["fxERC20RootTunnelAddress"], log + ", function: owner()");
}

// Check FxGovernorTunnel: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkFxGovernorTunnel(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const fxGovernorTunnel = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + fxGovernorTunnel.address;
    // Check the root governor
    const rootGovernor = await fxGovernorTunnel.rootGovernor();
    customExpect(rootGovernor, globalsInstance["timelockAddress"], log + ", function: rootGovernor()");

    // Check fxChild
    const fxChild = await fxGovernorTunnel.fxChild();
    customExpect(fxChild, globalsInstance["fxChildAddress"], log + ", function: fxChild()");
}

// Check FxERC20ChildTunnel: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkFxERC20ChildTunnel(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const fxERC20ChildTunnel = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + fxERC20ChildTunnel.address;
    // Check the child token
    const childToken = await fxERC20ChildTunnel.childToken();
    customExpect(childToken, globalsInstance["childTokenAddress"], log + ", function: childToken()");

    // Check the root token
    const rootToken = await fxERC20ChildTunnel.rootToken();
    customExpect(rootToken, globalsInstance["bridgedERC20Address"], log + ", function: rootToken()");

    // Check fxChild
    const fxChild = await fxERC20ChildTunnel.fxChild();
    customExpect(fxChild, globalsInstance["fxChildAddress"], log + ", function: fxChild()");

    // Check the fxRootTunnel
    const fxRootTunnel = await fxERC20ChildTunnel.fxRootTunnel();
    customExpect(fxRootTunnel, globalsInstance["fxERC20RootTunnelAddress"], log + ", function: fxRootTunnel()");
}

// Check FxERC20RootTunnel: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkFxERC20RootTunnel(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const fxERC20RootTunnel = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + fxERC20RootTunnel.address;
    // Check the child token
    const childToken = await fxERC20RootTunnel.childToken();
    customExpect(childToken, globalsInstance["childTokenAddress"], log + ", function: childToken()");

    // Check the root token
    const rootToken = await fxERC20RootTunnel.rootToken();
    customExpect(rootToken, globalsInstance["bridgedERC20Address"], log + ", function: rootToken()");

    // Check fxRoot
    const fxRoot = await fxERC20RootTunnel.fxRoot();
    customExpect(fxRoot, globalsInstance["fxRootAddress"], log + ", function: fxChild()");

    // Check the fxChildTunnel
    const fxChildTunnel = await fxERC20RootTunnel.fxChildTunnel();
    customExpect(fxChildTunnel, globalsInstance["fxERC20ChildTunnelAddress"], log + ", function: fxChildTunnel()");

    // Check the checkpointManager
    const checkpointManager = await fxERC20RootTunnel.checkpointManager();
    customExpect(checkpointManager, globalsInstance["checkpointManagerAddress"], log + ", function: checkpointManager()");
}

// Check HomeMediator: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkHomeMediator(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const homeMediator = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + homeMediator.address;
    // Check the foreign governor
    const foreignGovernor = await homeMediator.foreignGovernor();
    customExpect(foreignGovernor, globalsInstance["timelockAddress"], log + ", function: foreignGovernor()");

    // Check AMBContractProxyHomeAddress
    const proxyHome = await homeMediator.AMBContractProxyHome();
    customExpect(proxyHome, globalsInstance["AMBContractProxyHomeAddress"], log + ", function: AMBContractProxyHome()");
}

// Check OptimismMessenger: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkOptimismMessenger(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const optimismMessenger = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + optimismMessenger.address;
    // Check the foreign governor
    const sourceGovernor = await optimismMessenger.sourceGovernor();
    customExpect(sourceGovernor, globalsInstance["timelockAddress"], log + ", function: sourceGovernor()");

    // Check L2CrossDomainMessengerAddress
    const proxyHome = await optimismMessenger.CDMContractProxyHome();
    customExpect(proxyHome, globalsInstance["L2CrossDomainMessengerAddress"], log + ", function: CDMContractProxyHome()");
}

// Check WormholeMessenger: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkWormholeMessenger(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const wormholeMessenger = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + wormholeMessenger.address;
    // Check the source governor
    const sourceGovernor = await wormholeMessenger.sourceGovernor();
    customExpect(sourceGovernor, globalsInstance["timelockAddress"].toLowerCase(), log + ", function: sourceGovernor()");

    // Check L2WormholeRelayerAddress
    const wormholeRelayer = await wormholeMessenger.wormholeRelayer();
    customExpect(wormholeRelayer, globalsInstance["L2WormholeRelayerAddress"], log + ", function: wormholeRelayer()");

    // Check source governor chain Id
    const sourceGovernorChainId = await wormholeMessenger.sourceGovernorChainId();
    customExpect(sourceGovernorChainId.toString(), globalsInstance["sourceGovernorChainId"], log + ", function: sourceGovernorChainId()");
}

async function main() {
    // Check for the API keys
    if (!process.env.ALCHEMY_API_KEY_MAINNET || !process.env.ALCHEMY_API_KEY_GOERLI ||
        !process.env.ALCHEMY_API_KEY_MATIC || !process.env.ALCHEMY_API_KEY_MUMBAI) {
        console.log("Check API keys!");
        return;
    }

    // Read configuration from the JSON file
    const configFile = "docs/configuration.json";
    const dataFromJSON = fs.readFileSync(configFile, "utf8");
    const configs = JSON.parse(dataFromJSON);

    const numChains = configs.length;
    // ################################# VERIFY CONTRACTS WITH REPO #################################
    if (verifyRepo) {
        // For now gnosis chains are not supported
        const networks = {
            "mainnet": "etherscan",
            "goerli": "goerli.etherscan",
            "polygon": "polygonscan",
            "polygonMumbai": "testnet.polygonscan",
            "optimistic": "optimistic.etherscan"
        };

        console.log("\nVerifying deployed contracts vs the repo... If no error is output, then the contracts are correct.");

        // Traverse all chains
        for (let i = 0; i < numChains; i++) {
            // Skip gnosis chains
            if (!networks[configs[i]["name"]]) {
                continue;
            }

            console.log("\n\nNetwork:", configs[i]["name"]);
            const network = networks[configs[i]["name"]];
            const contracts = configs[i]["contracts"];

            // Verify contracts
            for (let j = 0; j < contracts.length; j++) {
                console.log("Checking " + contracts[j]["name"]);
                const execSync = require("child_process").execSync;
                try {
                    execSync("scripts/audit_chains/audit_repo_contract.sh " + network + " " + contracts[j]["name"] + " " + contracts[j]["address"]);
                } catch (error) {
                    continue;
                }
            }
        }
    }
    // ################################# /VERIFY CONTRACTS WITH REPO #################################

    // ################################# VERIFY CONTRACTS SETUP #################################
    if (verifySetup) {
        const globalNames = {
            "mainnet": "scripts/deployment/globals_mainnet.json",
            "goerli": "scripts/deployment/globals_goerli.json",
            "polygon": "scripts/deployment/bridges/polygon/globals_polygon_mainnet.json",
            "polygonMumbai": "scripts/deployment/bridges/polygon/globals_polygon_mumbai.json",
            "gnosis": "scripts/deployment/bridges/gnosis/globals_gnosis_mainnet.json",
            "chiado": "scripts/deployment/bridges/gnosis/globals_gnosis_chiado.json",
            "optimistic": "scripts/deployment/bridges/optimistic/globals_optimistic_mainnet.json",
            "optimisticSepolia": "scripts/deployment/bridges/optimistic/globals_optimistic_sepolia.json",
            "base": "scripts/deployment/bridges/optimistic/globals_base_mainnet.json",
            "baseSepolia": "scripts/deployment/bridges/optimistic/globals_base_sepolia.json",
            "celo": "scripts/deployment/bridges/wormhole/globals_celo_mainnet.json",
            "celoAlfajores": "scripts/deployment/bridges/wormhole/globals_celo_alfajores.json"
        };

        const providerLinks = {
            "mainnet": "https://eth-mainnet.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MAINNET,
            "goerli": "https://eth-goerli.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_GOERLI,
            "polygon": "https://polygon-mainnet.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MATIC,
            "polygonMumbai": "https://polygon-mumbai.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MUMBAI,
            "gnosis": "https://rpc.gnosischain.com",
            "chiado": "https://rpc.chiadochain.net",
            "optimistic": "https://optimism.drpc.org",
            "optimisticSepolia": "https://sepolia.optimism.io",
            "base": "https://mainnet.base.org",
            "baseSepolia": "https://sepolia.base.org",
            "celo": "https://forno.celo.org",
            "celoAlfajores": "https://alfajores-forno.celo-testnet.org"
        };

        // Get all the globals processed
        const globals = new Array();
        const providers = new Array();
        for (let i = 0; i < numChains; i++) {
            const dataJSON = fs.readFileSync(globalNames[configs[i]["name"]], "utf8");
            globals.push(JSON.parse(dataJSON));
            const provider = new ethers.providers.JsonRpcProvider(providerLinks[configs[i]["name"]]);
            providers.push(provider);
        }

        console.log("\nVerifying deployed contracts setup... If no error is output, then the contracts are correct.");

        // L1 contracts
        for (let i = 0; i < 2; i++) {
            console.log("\n######## Verifying setup on CHAIN ID", configs[i]["chainId"]);

            const initLog = "ChainId: " + configs[i]["chainId"] + ", network: " + configs[i]["name"];

            let log = initLog + ", contract: " + "OLAS";
            await checkOLAS(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "OLAS", log);

            log = initLog + ", contract: " + "Timelock";
            await checkTimelock(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "Timelock", log);

            log = initLog + ", contract: " + "veOLAS";
            await checkVEOLAS(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "veOLAS", log);

            log = initLog + ", contract: " + "buOLAS";
            await checkBUOLAS(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "buOLAS", log);

            log = initLog + ", contract: " + "wveOLAS";
            await checkWrappedVEOLAS(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "wveOLAS", log);

            log = initLog + ", contract: " + "GovernorOLAS";
            await checkGovernorOLAS(configs[i]["chainId"], providers[i], globals[i], globals[0], configs[i]["contracts"], "GovernorOLAS", log);

            log = initLog + ", contract: " + "GuardCM";
            await checkGuardCM(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "GuardCM", log);

            log = initLog + ", contract: " + "BridgedERC20";
            await checkBridgedERC20(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "BridgedERC20", log);

            log = initLog + ", contract: " + "FxERC20RootTunnel";
            await checkFxERC20RootTunnel(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "FxERC20RootTunnel", log);
        }

        // L2 contracts
        for (let i = 2; i < numChains; i++) {
            console.log("\n######## Verifying setup on CHAIN ID", configs[i]["chainId"]);

            const initLog = "ChainId: " + configs[i]["chainId"] + ", network: " + configs[i]["name"];

            if (configs[i]["chainId"] == "137" || configs[i]["chainId"] == "80001") {
                let log = initLog + ", contract: " + "FxGovernorTunnel";
                await checkFxGovernorTunnel(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "FxGovernorTunnel", log);

                log = initLog + ", contract: " + "FxERC20ChildTunnel";
                await checkFxERC20ChildTunnel(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "FxERC20ChildTunnel", log);
            } else if (configs[i]["chainId"] == "100" || configs[i]["chainId"] == "10200") {
                let log = initLog + ", contract: " + "HomeMediator";
                await checkHomeMediator(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "HomeMediator", log);
            } else if (configs[i]["chainId"] == "10" || configs[i]["chainId"] == "11155420" || configs[i]["chainId"] == "8453" || configs[i]["chainId"] == "84532") {
                let log = initLog + ", contract: " + "OptimismMessenger";
                await checkOptimismMessenger(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "OptimismMessenger", log);
            } else if (configs[i]["chainId"] == "42220" || configs[i]["chainId"] == "44787") {
                let log = initLog + ", contract: " + "WormholeMessenger";
                await checkWormholeMessenger(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "WormholeMessenger", log);
            }
        }
    }
    // ################################# /VERIFY CONTRACTS SETUP #################################
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });