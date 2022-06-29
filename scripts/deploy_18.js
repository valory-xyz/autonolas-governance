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
    const bu = await ethers.getContractAt("buOLAS", parsedData.buOLASAddress);
    const sale = await ethers.getContractAt("Sale", parsedData.saleAddress);
    console.log("14. EOA to transfer its minting and its owner rights to Timelock with by calling `changeMinter(Timelock)` and `changeOwner(Timelock)`");
    console.log("You are signing the following transaction: olas.connect(EOA).changeMinter(parsedData.timelockAddress)");
    let result = await olas.connect(EOA).changeMinter(parsedData.timelockAddress);
    // Transaction details
    console.log("Contract call: OLAS");
    console.log("Contract address:", olas.address);
    console.log("Transaction:", result.hash);

    console.log("You are signing the following transaction: olas.connect(EOA).changeOwner(parsedData.timelockAddress)");
    result = await olas.connect(EOA).changeOwner(parsedData.timelockAddress);
    // Transaction details
    console.log("Contract call: OLAS");
    console.log("Contract address:", olas.address);
    console.log("Transaction:", result.hash);

    console.log("15. EOA to transfer ownership rights of buOLAS to Timelock calling `changeOwner(Timelock)`");
    console.log("You are signing the following transaction: bu.connect(EOA).changeOwner(parsedData.timelockAddress)");
    result = await bu.connect(EOA).changeOwner(parsedData.timelockAddress);
    // Transaction details
    console.log("Contract call: buOLAS");
    console.log("Contract address:", bu.address);
    console.log("Transaction:", result.hash);

    console.log("16. EOA to transfer ownership rights of Sale to Valory multisig calling `changeOwner(ValoryMultisig)`");
    console.log("You are signing the following transaction: sale.connect(EOA).changeOwner(parsedData.valoryMultisig)");
    result = await sale.connect(EOA).changeOwner(parsedData.valoryMultisig);
    // Transaction details
    console.log("Contract call: Sale");
    console.log("Contract address:", sale.address);
    console.log("Transaction:", result.hash);

    // Verification of ownership and values
    expect(await olas.owner()).to.equal(parsedData.timelockAddress);
    expect(await olas.minter()).to.equal(parsedData.timelockAddress);
    expect(await bu.owner()).to.equal(parsedData.timelockAddress);
    expect(await sale.owner()).to.equal(parsedData.valoryMultisig);

    console.log("17. EOA to revoke self admin rights from the Timelock (via `renounceRole()`)");
    const timelock = await ethers.getContractAt("Timelock", parsedData.timelockAddress);
    const adminRole = ethers.utils.id("TIMELOCK_ADMIN_ROLE");
    console.log("You are signing the following transaction: timelock.connect(EOA).renounceRole(adminRole, await EOA.getAddress())");
    result = await timelock.connect(EOA).renounceRole(adminRole, await EOA.getAddress());
    // Transaction details
    console.log("Contract call: Timelock");
    console.log("Contract address:", timelock.address);
    console.log("Transaction:", result.hash);
    // Check for the admin role being revoked from the EOA
    expect(await timelock.hasRole(adminRole, deployer)).to.equal(false);

    console.log("18. EOA to revoke self ownership rights from deploymentFactory to Null Address (via `changeOwner()`)");
    const factory = await ethers.getContractAt("DeploymentFactory", parsedData.deploymentFactory);
    console.log("You are signing the following transaction: factory.connect(EOA).changeOwner(\"0x000000000000000000000000000000000000dEaD\")");
    result = await factory.connect(EOA).changeOwner("0x000000000000000000000000000000000000dEaD");
    // Transaction details
    console.log("Contract call: DeploymentFactory");
    console.log("Contract address:", factory.address);
    console.log("Transaction:", result.hash);
    // Check the ownership of the deployment factory
    expect(await factory.owner()).to.equal("0x000000000000000000000000000000000000dEaD");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });