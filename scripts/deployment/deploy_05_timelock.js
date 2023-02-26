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
    const CMAddress = parsedData.CM;
    const derivationPath = parsedData.derivationPath;
    const providerName = parsedData.providerName;
    const minDelay = parsedData.timelockMinDelay;
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

    console.log("5. EOA to deploy the Timelock contract with the proposer (\"PROPOSER_ROLE\"), executor (\"EXECUTOR_ROLE\"), and canceller (\"CANCELLER_ROLE\") roles given to the CM (via deployment with \"proposers\" and \"executors\" parameters being the CM address)");
    const proposers = [CMAddress];
    const executors = [CMAddress];
    const Timelock = await ethers.getContractFactory("Timelock");
    console.log("You are signing the following transaction: Timelock.connect(EOA).deploy(minDelay, proposers, executors)");
    const timelock = await Timelock.connect(EOA).deploy(minDelay, proposers, executors);
    const result = await timelock.deployed();

    // Transaction details
    console.log("Contract deployment: Timelock");
    console.log("Contract address:", timelock.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Verification of ownership and values
    const adminRole = ethers.utils.id("TIMELOCK_ADMIN_ROLE");
    const proposerRole = ethers.utils.id("PROPOSER_ROLE");
    const executorRole = ethers.utils.id("EXECUTOR_ROLE");
    const cancellerRole = ethers.utils.id("CANCELLER_ROLE");
    expect(await timelock.hasRole(adminRole, deployer)).to.equal(true);
    expect(await timelock.hasRole(adminRole, timelock.address)).to.equal(true);
    expect(await timelock.hasRole(adminRole, CMAddress)).to.equal(false);
    expect(await timelock.hasRole(executorRole, CMAddress)).to.equal(true);
    expect(await timelock.hasRole(proposerRole, CMAddress)).to.equal(true);
    expect(await timelock.hasRole(cancellerRole, CMAddress)).to.equal(true);

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --contract contracts/Timelock.sol:Timelock --constructor-args scripts/deployment/verify_05_timelock.js --network " + providerName + " " + timelock.address, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.timelockAddress = timelock.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });