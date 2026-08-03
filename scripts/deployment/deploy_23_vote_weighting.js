/*global process*/

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
    console.log("23. EOA to deploy VoteWeighting contract pointed to veOLAS and the Dispenser");
    const VoteWeighting = await ethers.getContractFactory("VoteWeighting");
    // Note: the dispenser is immutable and set at construction; the Dispenser must be deployed beforehand.
    // Use the zero address for a general-purpose deployment with no dispenser.
    const dispenserAddress = parsedData.dispenserAddress || ethers.constants.AddressZero;
    console.log("You are signing the following transaction: VoteWeighting.connect(EOA).deploy(veOLAS, dispenser)");
    const voteWeighting = await VoteWeighting.connect(EOA).deploy(parsedData.veOLASAddress, dispenserAddress);
    const result = await voteWeighting.deployed();

    // Transaction details
    console.log("Contract deployment: voteWeighting");
    console.log("Contract address:", voteWeighting.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // If on sepolia, wait half a minute for the transaction completion
    if (providerName === "sepolia") {
        await new Promise(r => setTimeout(r, 30000));
    }

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_23_vote_weighting.js --network " + providerName + " " + voteWeighting.address, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.voteWeightingAddress = voteWeighting.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });