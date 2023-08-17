/*global process*/

const { ethers } = require("ethers");
const { expect } = require("chai");
const fs = require("fs");

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

// Custom expect for contain clause that is wrapped into try / catch block
function customExpectWithIn(arg1, arg2, arg3, log) {
    try {
        expect(arg1).within(arg2,arg3);
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
            console.log("\nContract name", configContracts[i]["name"]);
            console.log("Contract address", configContracts[i]["address"]);
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
}

// Check veOLAS: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkVEOLAS(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const veOLAS = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + veOLAS.address;
    // Check current token
    const olas = await veOLAS.token();
    customExpect(olas, globalsInstance["olasAddress"], log + ", function: token()");

}

// Check buOLAS: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkBUOLAS(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const buOLAS = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + buOLAS.address;
    // Check current token
    const olas = await buOLAS.token();
    customExpect(olas, globalsInstance["olasAddress"], log + ", function: token()");

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
    const olas = await wveOLAS.token();
    customExpect(olas, globalsInstance["olasAddress"], log + ", function: token()");
    
    // Check ve
    const ve = await wveOLAS.ve();
    customExpect(ve, globalsInstance["veOLASAddress"], log + ", function: ve()");
}

// Check GolvernorOLAS: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkGovernorOLAS(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const governor = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + governor.address;
    // Check current token
    const wveOLAS = await governor.token();
    customExpect(wveOLAS, globalsInstance["wveOLASAddress"], log + ", function: token()");
    // Check timelock
    const timelock = await governor.timelock();
    customExpect(timelock, globalsInstance["timelockAddress"], log + ", function: timelock()");
    // Check version, hardcoded
    const version = await governor.version();
    customExpect(version, "1", log + ", function: version()");
    // Check quorumNumerator, hardcoded
    const quorumNumerator = await governor.quorumNumerator();
    customExpect(quorumNumerator, "3", log + ", function: quorumNumerator()");
    // Check votingDelay, hardcoded 2 days => 86400 * 2 / 12.43 = 13901
    // 86400 * 2 / 11 = 15709 to 86400 * 2 / 15 = 11250
    const vDelay = await governor.votingDelay();
    customExpectWithIn(vDelay, "11250","13901", log + ", function: votingDelay()");
    // Check quorumNumerator, hardcoded 2 days => 86400 * 3 / 13.2 = 19639
    // 86400 * 3 / 11 = 23563 to 86400 * 3 / 15 = 17280
    const vPeriod = await governor.votingPeriod();
    customExpectWithIn(vPeriod, "17280","23563", log + ", function: votingPeriod()");

}

// Check FxGovernorTunnel: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkFxGovernorTunnel(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const fxGovernorTunnel = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + fxGovernorTunnel.address;
}

// Check HomeMediator: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkHomeMediator(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const homeMediator = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + homeMediator.address;
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
    // For now gnosis chains are not supported
    const networks = {
        "mainnet": "etherscan",
        "goerli": "goerli.etherscan",
        "polygon": "polygonscan",
        "polygonMumbai": "testnet.polygonscan"
    };

    //    console.log("\nVerifying deployed contracts vs the repo... If no error is output, then the contracts are correct.");
    //
    //    // Traverse all chains
    //    for (let i = 0; i < numChains; i++) {
    //        // Skip gnosis chains
    //        if (!networks[configs[i]["name"]]) {
    //            continue;
    //        }
    //
    //        console.log("\n\nNetwork:", configs[i]["name"]);
    //        const network = networks[configs[i]["name"]];
    //        const contracts = configs[i]["contracts"];
    //
    //        // Verify contracts
    //        for (let j = 0; j < contracts.length; j++) {
    //            console.log("Checking " + contracts[j]["name"]);
    //            const execSync = require("child_process").execSync;
    //            try {
    //                execSync("scripts/audit_chains/audit_repo_contract.sh " + network + " " + contracts[j]["name"] + " " + contracts[j]["address"]);
    //            } catch (error) {
    //            }
    //        }
    //    }
    //    // ################################# /VERIFY CONTRACTS WITH REPO #################################

    // ################################# VERIFY CONTRACTS SETUP #################################
    const globalNames = {
        "mainnet": "scripts/deployment/globals_mainnet.json",
        "goerli": "scripts/deployment/globals_goerli.json",
        "polygon": "scripts/deployment/bridges/polygon/globals_polygon_mainnet.json",
        "polygonMumbai": "scripts/deployment/bridges/polygon/globals_polygon_mumbai.json",
        "gnosis": "scripts/deployment/bridges/gnosis/globals_gnosis_mainnet.json",
        "chiado": "scripts/deployment/bridges/gnosis/globals_gnosis_chiado.json"
    };

    const providerLinks = {
        "mainnet": "https://eth-mainnet.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MAINNET,
        "goerli": "https://eth-goerli.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_GOERLI,
        "polygon": "https://polygon-mainnet.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MATIC,
        "polygonMumbai": "https://polygon-mumbai.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MUMBAI,
        "gnosis": "https://rpc.gnosischain.com",
        "chiado": "https://rpc.chiadochain.net"
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
        await checkGovernorOLAS(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "GovernorOLAS", log);
    }

    // L2 contracts
    for (let i = 2; i < numChains; i++) {
        console.log("\n######## Verifying setup on CHAIN ID", configs[i]["chainId"]);

        const initLog = "ChainId: " + configs[i]["chainId"] + ", network: " + configs[i]["name"];

        let log = initLog + ", contract: " + "BridgeMediator";
        if (configs[i]["chainId"] == "137" || configs[i]["chainId"] == "80001") {
            await checkFxGovernorTunnel(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "FxGovernorTunnel", log);
        } else {
            await checkHomeMediator(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "HomeMediator", log);
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