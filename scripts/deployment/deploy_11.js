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
    console.log("11. EOA to deploy Sale contract pointed to OLAS, veOLAs and bOLAS");
    const SALE = await ethers.getContractFactory("Sale");
    console.log("You are signing the following transaction: SALE.connect(EOA).deploy(parsedData.olasAddress, parsedData.veOLASAddress, parsedData.buOLASAddress)");
    const sale = await SALE.connect(EOA).deploy(parsedData.olasAddress, parsedData.veOLASAddress, parsedData.buOLASAddress);
    const result = await sale.deployed();

    // Transaction details
    console.log("Contract deployment: Sale");
    console.log("Contract address:", sale.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Verification of ownership and values
    expect(await sale.olasToken()).to.equal(parsedData.olasAddress);
    expect(await sale.veToken()).to.equal(parsedData.veOLASAddress);
    expect(await sale.buToken()).to.equal(parsedData.buOLASAddress);
    expect(await sale.owner()).to.equal(deployer);

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_11.js --network " + providerName + " " + sale.address, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.saleAddress = sale.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });