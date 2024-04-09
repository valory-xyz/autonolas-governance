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
    console.log("1. EOA to deploy WormholeL2ReceiverL1Sender contract");
    const WormholeL2ReceiverL1Sender = await ethers.getContractFactory("WormholeL2ReceiverL1Sender");
    console.log("You are signing the following transaction: WormholeL2ReceiverL1Sender.connect(EOA).deploy()");
    const wormholeL2ReceiverL1Sender = await WormholeL2ReceiverL1Sender.connect(EOA).deploy(parsedData.L2WormholeRelayerAddress,
        parsedData.sourceChainId, parsedData.wormholeL1ReceiverAddress);
    const result = await wormholeL2ReceiverL1Sender.deployed();

    // Transaction details
    console.log("Contract deployment: WormholeL2ReceiverL1Sender");
    console.log("Contract address:", wormholeL2ReceiverL1Sender.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Writing updated parameters back to the JSON file
    parsedData.wormholeL2ReceiverL1SenderAddress = wormholeL2ReceiverL1Sender.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/bridges/wormhole/test/l1_l2_l1/verify_03_womholel2receiverl1sender.js --network " + providerName + " " + wormholeL2ReceiverL1Sender.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
