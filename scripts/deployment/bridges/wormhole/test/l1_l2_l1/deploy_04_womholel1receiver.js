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
    const providerName = "sepolia";
    let EOA;

    const provider = await ethers.providers.getDefaultProvider(providerName);
    const signers = await ethers.getSigners();

    if (useLedger) {
        EOA = new LedgerSigner(provider, derivationPath);
    } else {
        EOA = signers[0];
    }
    // EOA address
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    // Transaction signing and execution
    console.log("1. EOA to deploy WormholeL1Receiver contract");
    const WormholeL1Receiver = await ethers.getContractFactory("WormholeL1Receiver");
    console.log("You are signing the following transaction: WormholeL1Receiver.connect(EOA).deploy()");
    const wormholeL1Receiver = await WormholeL1Receiver.connect(EOA).deploy();
    const result = await wormholeL1Receiver.deployed();

    // Transaction details
    console.log("Contract deployment: WormholeL1Receiver");
    console.log("Contract address:", wormholeL1Receiver.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Writing updated parameters back to the JSON file
    parsedData.wormholeL1ReceiverAddress = wormholeL1Receiver.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --network " + providerName + " " + wormholeL1Receiver.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
