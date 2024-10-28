/*global process*/

const { expect } = require("chai");
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
    console.log("24. EOA to deploy Burner contract pointed to OLAS");
    const Burner = await ethers.getContractFactory("Burner");
    console.log("You are signing the following transaction: Burner.connect(EOA).deploy(OLAS)");
    const burner = await Burner.connect(EOA).deploy(parsedData.olasAddress);
    const result = await burner.deployed();

    // Transaction details
    console.log("Contract deployment: burner");
    console.log("Contract address:", burner.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // If on sepolia, wait half a minute for the transaction completion
    if (providerName === "sepolia") {
        await new Promise(r => setTimeout(r, 30000));
    }

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_24_burner.js --network " + providerName + " " + burner.address, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.burnerAddress = burner.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });