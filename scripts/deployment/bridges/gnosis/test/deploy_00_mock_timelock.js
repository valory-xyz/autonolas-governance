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
    const providerName = "goerli";
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
    console.log("1. EOA to deploy mock timelock contract");
    const Timelock = await ethers.getContractFactory("MockTimelock");
    console.log("You are signing the following transaction: Timelock.connect(EOA).deploy(AMBContractProxyForeignAddress)");
    const timelock = await Timelock.connect(EOA).deploy(parsedData.AMBContractProxyForeignAddress);
    const result = await timelock.deployed();

    // Transaction details
    console.log("Contract deployment: MockTimelock");
    console.log("Contract address:", timelock.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Writing updated parameters back to the JSON file
    parsedData.timelockAddress = timelock.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/bridges/gnosis/test/verify_00_mock_timelock.js --network " + providerName + " " + timelock.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
