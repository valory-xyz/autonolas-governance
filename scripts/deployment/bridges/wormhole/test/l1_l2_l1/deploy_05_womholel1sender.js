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
    let EOA;

    const provider = new ethers.providers.JsonRpcProvider(parsedData.networkURL);
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
    console.log("1. EOA to deploy WormholeL1Sender contract");
    const WormholeL1Sender = await ethers.getContractFactory("WormholeL1Sender");
    console.log("You are signing the following transaction: WormholeL1Sender.connect(EOA).deploy()");
    const wormholeL1Sender = await WormholeL1Sender.connect(EOA).deploy(parsedData.L2WormholeRelayerAddress,
        parsedData.sourceChainId, parsedData.wormholeL1ReceiverAddress);
    const result = await wormholeL1Sender.deployed();

    // Transaction details
    console.log("Contract deployment: WormholeL1Sender");
    console.log("Contract address:", wormholeL1Sender.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Writing updated parameters back to the JSON file
    parsedData.wormholeL1SenderAddress = wormholeL1Sender.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/bridges/wormhole/test/l1_l2_l1/verify_05_womholel1sender.js --network " + providerName + " " + wormholeL1Sender.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
