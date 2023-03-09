/*global process*/

const { expect } = require("chai");
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
    // Valory (sent to Valory multisig);
    const initSupply = parsedData.initSupply;
    // Numbers below must accumulate to initSupply
    const timelockSupply = parsedData.timelockSupply;
    const saleSupply = parsedData.saleSupply;
    const valorySupply = parsedData.valorySupply;

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
    const olas = await ethers.getContractAt("OLAS", parsedData.olasAddress);
    console.log("11. EOA to mint initial OLAS supply for DAO treasury (sent to Timelock), DAO members (sent to Sale contract) and Valory multisig");

    console.log("You are signing the following transaction: olas.connect(EOA).mint(parsedData.timelockAddress, timelockSupply)");
    console.log("Address to mint to:", parsedData.timelockAddress);
    console.log("Amount to mint:", timelockSupply);
    let result = await olas.connect(EOA).mint(parsedData.timelockAddress, timelockSupply);
    // Transaction details
    console.log("Contract call: OLAS");
    console.log("Contract address:", olas.address);
    console.log("Transaction:", result.hash);

    console.log("You are signing the following transaction: olas.connect(EOA).mint(parsedData.saleAddress, saleSupply)");
    console.log("Address to mint to:", parsedData.saleAddress);
    console.log("Amount to mint:", saleSupply);
    result = await olas.connect(EOA).mint(parsedData.saleAddress, saleSupply);
    // Transaction details
    console.log("Contract call: OLAS");
    console.log("Contract address:", olas.address);
    console.log("Transaction:", result.hash);

    console.log("You are signing the following transaction: olas.connect(EOA).mint(parsedData.valoryMultisig, valorySupply)");
    console.log("Address to mint to:", parsedData.valoryMultisig);
    console.log("Amount to mint:", valorySupply);
    result = await olas.connect(EOA).mint(parsedData.valoryMultisig, valorySupply);
    // Transaction details
    console.log("Contract call: OLAS");
    console.log("Contract address:", olas.address);
    console.log("Transaction:", result.hash);

    // Check the balance of contracts to be equal to initial supply in total
    const balanceTimelock = BigInt(await olas.balanceOf(parsedData.timelockAddress));
    const balanceSale = BigInt(await olas.balanceOf(parsedData.saleAddress));
    const balanceValory = BigInt(await olas.balanceOf(parsedData.valoryMultisig));
    const sumBalance = balanceTimelock + balanceSale + balanceValory;
    expect(sumBalance).to.equal(BigInt(initSupply));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });