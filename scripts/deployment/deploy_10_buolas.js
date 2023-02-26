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
    console.log("10. EOA to deploy buOLAS contract pointed to OLAS");
    const BU = await ethers.getContractFactory("buOLAS");
    console.log("You are signing the following transaction: BU.connect(EOA).deploy(parsedData.olasAddress, \"Burnable Locked OLAS\", \"buOLAS\")");
    const bu = await BU.connect(EOA).deploy(parsedData.olasAddress, "Burnable Locked OLAS", "buOLAS");
    const result = await bu.deployed();

    // Transaction details
    console.log("Contract deployment: buOLAS");
    console.log("Contract address:", bu.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Verification of ownership and values
    expect(await bu.token()).to.equal(parsedData.olasAddress);
    expect(await bu.name()).to.equal("Burnable Locked OLAS");
    expect(await bu.symbol()).to.equal("buOLAS");
    expect(await bu.owner()).to.equal(deployer);

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_10_buolas.js --network " + providerName + " " + bu.address, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.buOLASAddress = bu.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });