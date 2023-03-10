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
    console.log("16. EOA to deploy wveOLAS contract pointed to veOLAS and OLAS");
    const WVE = await ethers.getContractFactory("wveOLAS");
    console.log("You are signing the following transaction: wveOLAS.connect(EOA).deploy(parsedData.veOLASAddress, parsedData.olasAddress)");
    const wveOLAS = await WVE.connect(EOA).deploy(parsedData.veOLASAddress, parsedData.olasAddress);
    const result = await wveOLAS.deployed();
    // If on goerli, wait a minute for the transaction completion
    if (providerName === "goerli") {
        await new Promise(r => setTimeout(r, 60000));
    }

    // Transaction details
    console.log("Contract deployment: wveOLAS");
    console.log("Contract address:", wveOLAS.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Verification of values
    expect(await wveOLAS.ve()).to.equal(parsedData.veOLASAddress);

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_16_wveolas.js --network " + providerName + " " + wveOLAS.address, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.wveOLASAddress = wveOLAS.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });