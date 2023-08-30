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
    console.log("18. EOA to deploy community multisig Guard");
    const GuardCM = await ethers.getContractFactory("GuardCM");
    console.log("You are signing the following transaction: GuardCM.connect(EOA).deploy(parsedData.timelockAddress, parsedData.CM, parsedData.governorTwoAddress)");
    const guardCM = await GuardCM.connect(EOA).deploy(parsedData.timelockAddress, parsedData.CM, parsedData.governorTwoAddress);
    let result = await guardCM.deployed();

    // Transaction details
    console.log("Contract deployment: GuardCM");
    console.log("Contract address:", guardCM.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // If on goerli, wait a minute for the transaction completion
    if (providerName === "goerli") {
        await new Promise(r => setTimeout(r, 60000));
    }

    // Writing updated parameters back to the JSON file
    parsedData.guardCMAddress = guardCM.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_18_guardCM.js --network " + providerName + " " + guardCM.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });