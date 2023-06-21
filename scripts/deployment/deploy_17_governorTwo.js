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
    console.log("17. EOA to deploy GovernorOLAS contract with wveOLAS and Timelock addresses as input parameters and other defined governor-related parameters");
    const maxPriorityFeePerGasInGwei = "2";
    const maxFeePerGasInGwei = "36";

    const maxPriorityFeePerGas = ethers.utils.parseUnits(maxPriorityFeePerGasInGwei, "gwei");
    const maxFeePerGas = ethers.utils.parseUnits(maxFeePerGasInGwei, "gwei");

    const GovernorOLAS = await ethers.getContractFactory("GovernorOLAS");
    console.log("You are signing the following transaction: GovernorOLAS.connect(EOA).deploy(parsedData.wveOLASAddress, parsedData.timelockAddress, initialVotingDelay, initialVotingPeriod, initialProposalThreshold, quorum)");
    const governor = await GovernorOLAS.connect(EOA).deploy(parsedData.wveOLASAddress, parsedData.timelockAddress, initialVotingDelay,
        initialVotingPeriod, initialProposalThreshold, quorum, { maxPriorityFeePerGas, maxFeePerGas });
    let result = await governor.deployed();

    // Transaction details
    console.log("Contract deployment: GovernorOLAS");
    console.log("Contract address:", governor.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Writing updated parameters back to the JSON file
    parsedData.governorTwoAddress = governor.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Verification of ownership and values
    expect(await governor.name()).to.equal("Governor OLAS");
    expect(await governor.proposalThreshold()).to.equal(initialProposalThreshold);
    expect(await governor.votingDelay()).to.equal(initialVotingDelay);
    expect(await governor.votingPeriod()).to.equal(initialVotingPeriod);
    expect(await governor.timelock()).to.equal(parsedData.timelockAddress);

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_17_governorTwo.js --network " + providerName + " " + governor.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });