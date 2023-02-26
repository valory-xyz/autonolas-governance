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
    const olasSaltString = parsedData.olasSaltString;
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
    console.log("3. Brutforce salt for vanity address OLAS (deployAddress + bytecode)");
    const olasSalt = olasSaltString;

    console.log("4. EOA to deploy OLAS contract via deploymentFactory (becoming its owner and minter)");
    const factory = await ethers.getContractAt("DeploymentFactory", parsedData.deploymentFactory);
    console.log("You are signing the following transaction: factory.connect(EOA).deployOLAS(olasSalt)");
    const result = await factory.connect(EOA).deployOLAS(olasSalt);
    const olasAddress = await factory.olasAddress();
    const olas = await ethers.getContractAt("OLAS", olasAddress);

    // Transaction details
    console.log("Contract deployment: OLAS via create2()");
    console.log("Contract address:", olasAddress);
    console.log("Transaction:", result.hash);

    // Verification of ownership and values
    expect(deployer).to.equal(await olas.owner());
    expect(deployer).to.equal(await olas.minter());

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --network " + providerName + " " + olasAddress, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.olasAddress = olasAddress;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });