/*global process*/

const { expect } = require("chai");
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
    console.log("2. EOA to deploy deploymentFactory and get deploymentAddress of deploymentFactory;");
    const FACTORY = await ethers.getContractFactory("DeploymentFactory");
    console.log("You are signing the following transaction: FACTORY.connect(EOA).deploy()");
    const factory = await FACTORY.connect(EOA).deploy();
    const result = await factory.deployed();

    // Transaction details
    console.log("Contract deployment: DeploymentFactory");
    console.log("Contract address:", factory.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Verification of ownership and values
    expect(await factory.owner()).to.equal(deployer);

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --network " + providerName + " " + factory.address, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.deploymentFactory = factory.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
