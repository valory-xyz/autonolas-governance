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
    const veOlasSaltString = parsedData.veOlasSaltString;
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
    console.log("6. Brutforce salt for vanity address veOLAS (deployAddress + OLAS address + bytecode)");
    const veSalt = veOlasSaltString;

    console.log("7. EOA to deploy veOLAS contract via deploymentFactory pointed to OLAS");
    const factory = await ethers.getContractAt("DeploymentFactory", parsedData.deploymentFactory);
    console.log("You are signing the following transaction: factory.connect(EOA).deployVeOLAS(veSalt, parsedData.olasAddress)");
    const result = await factory.connect(EOA).deployVeOLAS(veSalt, parsedData.olasAddress);
    const veOLASAddress = await factory.veOLASAddress();
    const ve = await ethers.getContractAt("veOLAS", veOLASAddress);

    // Transaction details
    console.log("Contract deployment: veOLAS via create2()");
    console.log("Contract address:", veOLASAddress);
    console.log("Transaction:", result.hash);

    // Verification of ownership and values
    expect(await ve.token()).to.equal(parsedData.olasAddress);
    expect(await ve.name()).to.equal("Voting Escrow OLAS");
    expect(await ve.symbol()).to.equal("veOLAS");

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_07_veolas.js --network " + providerName + " " + veOLASAddress, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.veOLASAddress = veOLASAddress;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });