/*global process*/

const { expect } = require("chai");
const { ethers } = require("hardhat");
const { LedgerSigner } = require("@anders-t/ethers-ledger");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    let dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const derivationPath = parsedData.derivationPath;
    const useLedger = parsedData.useLedger;
    const providerName = parsedData.providerName;
    const claimableBalancesJSON = "claimableBalances.json";
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
    const sale = await ethers.getContractAt("Sale", parsedData.saleAddress);
    console.log("13. EOA to send transaction to Sale contract (`createBalancesFor()`) to create balances for initial DAO members for them to claim and lock later with veOLAS and buOLAS; Read the data from JSON file");
    dataFromJSON = fs.readFileSync(claimableBalancesJSON, "utf8");
    parsedData = JSON.parse(dataFromJSON);
    // Get veOLAS-related set of arrays
    const veOLASData = parsedData["veOLAS"];
    // Get buOLAS-related set of arrays
    const buOLASData = parsedData["buOLAS"];
    console.log("You are signing the following transaction: sale.connect(EOA).createBalancesFor(veOLASData, buOLASData)");
    console.log("The balances are taken from this JSON file:", claimableBalancesJSON);
    const result = await sale.connect(EOA).createBalancesFor(veOLASData["addresses"], veOLASData["amounts"], veOLASData["lockTimes"],
        buOLASData["addresses"], buOLASData["amounts"], buOLASData["numSteps"]);

    // Transaction details
    console.log("Contract call: Sale");
    console.log("Contract address:", sale.address);
    console.log("Transaction:", result.hash);

    // Check veOLAS and buOLAS for the claimable addresses
    for (let i = 0; i < veOLASData["addresses"].length; i++) {
        const balances = await sale.claimableBalances(veOLASData["addresses"][i]);
        expect(balances.veBalance).to.equal(veOLASData["amounts"][i]);
    }

    for (let i = 0; i < buOLASData["addresses"].length; i++) {
        const balances = await sale.claimableBalances(buOLASData["addresses"][i]);
        expect(balances.buBalance).to.equal(buOLASData["amounts"][i]);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });