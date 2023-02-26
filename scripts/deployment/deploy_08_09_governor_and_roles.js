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
    const initialVotingDelay = parsedData.initialVotingDelay;
    const initialVotingPeriod = parsedData.initialVotingPeriod;
    const initialProposalThreshold = parsedData.initialProposalThreshold;
    const quorum = parsedData.quorum;
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
    console.log("8. EOA to deploy GovernorOLAS contract with veOLAS and Timelock addresses as input parameters and other defined governor-related parameters");
    const GovernorOLAS = await ethers.getContractFactory("GovernorOLAS");
    console.log("You are signing the following transaction: GovernorOLAS.connect(EOA).deploy(parsedData.veOLASAddress, parsedData.timelockAddress, initialVotingDelay, initialVotingPeriod, initialProposalThreshold, quorum)");
    const governor = await GovernorOLAS.connect(EOA).deploy(parsedData.veOLASAddress, parsedData.timelockAddress, initialVotingDelay,
        initialVotingPeriod, initialProposalThreshold, quorum);
    let result = await governor.deployed();

    // Transaction details
    console.log("Contract deployment: GovernorOLAS");
    console.log("Contract address:", governor.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Verification of ownership and values
    expect(await governor.name()).to.equal("Governor OLAS");
    expect(await governor.proposalThreshold()).to.equal(initialProposalThreshold);
    expect(await governor.votingDelay()).to.equal(initialVotingDelay);
    expect(await governor.votingPeriod()).to.equal(initialVotingPeriod);
    expect(await governor.timelock()).to.equal(parsedData.timelockAddress);

    // Transaction signing and execution
    console.log("9. EOA to give admin (\"TIMELOCK_ADMIN_ROLE\"), proposer (\"PROPOSER_ROLE\"), executor (\"EXECUTOR_ROLE\"), and canceller (\"CANCELLER_ROLE\") roles to GovernorOLAS from Timelock (in separate transactions via \"grantRole()\" calls)");
    const adminRole = ethers.utils.id("TIMELOCK_ADMIN_ROLE");
    const proposerRole = ethers.utils.id("PROPOSER_ROLE");
    const executorRole = ethers.utils.id("EXECUTOR_ROLE");
    const cancellerRole = ethers.utils.id("CANCELLER_ROLE");
    const timelock = await ethers.getContractAt("Timelock", parsedData.timelockAddress);

    console.log("You are signing the following transaction: timelock.connect(EOA).grantRole(adminRole, governor.address)");
    result = await timelock.connect(EOA).grantRole(adminRole, governor.address);
    // Transaction details
    console.log("Contract call: Timelock");
    console.log("Contract address:", timelock.address);
    console.log("Transaction:", result.hash);

    console.log("You are signing the following transaction: timelock.connect(EOA).grantRole(executorRole, governor.address)");
    result = await timelock.connect(EOA).grantRole(executorRole, governor.address);
    // Transaction details
    console.log("Contract call: Timelock");
    console.log("Contract address:", timelock.address);
    console.log("Transaction:", result.hash);

    console.log("You are signing the following transaction: timelock.connect(EOA).grantRole(proposerRole, governor.address)");
    result = await timelock.connect(EOA).grantRole(proposerRole, governor.address);
    // Transaction details
    console.log("Contract call: Timelock");
    console.log("Contract address:", timelock.address);
    console.log("Transaction:", result.hash);

    console.log("You are signing the following transaction: timelock.connect(EOA).grantRole(cancellerRole, governor.address)");
    result = await timelock.connect(EOA).grantRole(cancellerRole, governor.address);
    // Transaction details
    console.log("Contract call: Timelock");
    console.log("Contract address:", timelock.address);
    console.log("Transaction:", result.hash);

    // Verification of ownership and values
    expect(await timelock.hasRole(adminRole, governor.address)).to.equal(true);
    expect(await timelock.hasRole(executorRole, governor.address)).to.equal(true);
    expect(await timelock.hasRole(proposerRole, governor.address)).to.equal(true);
    expect(await timelock.hasRole(cancellerRole, governor.address)).to.equal(true);

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_08_09_governor_and_roles.js --network " + providerName + " " + governor.address, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.governorAddress = governor.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });