/*global process*/

const { ethers } = require("hardhat");
const { LedgerSigner } = require("@anders-t/ethers-ledger");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const derivationPath = parsedData.derivationPath;
    const useLedger = parsedData.useLedger;
    const providerName = parsedData.providerName;
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
    console.log("25. EOA to deploy WormholeRelayer contract");
    const WormholeRelayer = await ethers.getContractFactory("WormholeRelayer");
    console.log("You are signing the following transaction: WormholeRelayer.connect(EOA).deploy(OLAS)");
    const wormholeRelayer = await WormholeRelayer.connect(EOA).deploy(parsedData.wormholeL1MessageRelayerAddress);
    const result = await wormholeRelayer.deployed();

    // Transaction details
    console.log("Contract deployment: wormholeRelayer");
    console.log("Contract address:", wormholeRelayer.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // If on sepolia, wait half a minute for the transaction completion
    if (providerName === "sepolia") {
        await new Promise(r => setTimeout(r, 30000));
    }

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_25_wormhole_relayer.js --network " + providerName + " " + wormholeRelayer.address, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.wormholeRelayerAddress = wormholeRelayer.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });