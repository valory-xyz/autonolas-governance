/*global process*/

const { ethers } = require("hardhat");
const { LedgerSigner } = require("@anders-t/ethers-ledger");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const useLedger = parsedData.useLedger;
    const derivationPath = parsedData.derivationPath;
    const providerName = parsedData.providerName;
    const gasPriceInGwei = parsedData.gasPriceInGwei;

    const networkURL = parsedData.networkURL;
    const provider = new ethers.providers.JsonRpcProvider(networkURL);
    const signers = await ethers.getSigners();

    let EOA;
    if (useLedger) {
        EOA = new LedgerSigner(provider, derivationPath);
    } else {
        EOA = signers[0];
    }
    // EOA address
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    // Transaction signing and execution
    console.log("1. EOA to deploy home mediator contract");
    const OptimismMessenger = await ethers.getContractFactory("OptimismMessenger");
    console.log("You are signing the following transaction: OptimismMessenger.connect(EOA).deploy(L2CrossDomainMessengerAddress, timelockAddress)");
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");
    const optimismMessenger = await OptimismMessenger.connect(EOA).deploy(parsedData.L2CrossDomainMessengerAddress, parsedData.timelockAddress, { gasPrice });
    const result = await optimismMessenger.deployed();

    // Transaction details
    console.log("Contract deployment: OptimismMessenger");
    console.log("Contract address:", optimismMessenger.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Writing updated parameters back to the JSON file
    parsedData.optimismMessengerAddress = optimismMessenger.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/bridges/optimistic/verify_01_optimism_messenger.js --network " + providerName + " " + optimismMessenger.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
