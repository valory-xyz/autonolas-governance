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
    console.log("19. EOA to deploy bridged ERC20 contract");
    const BridgedERC20 = await ethers.getContractFactory("BridgedERC20");
    console.log("You are signing the following transaction: BridgedERC20.connect(EOA).deploy()");

    const bridgedERC20 = await BridgedERC20.connect(EOA).deploy("50WMATIC-50OLAS from Polygon (POS)", "W-50WMATIC-50OLAS", 18);
    let result = await bridgedERC20.deployed();

    // Transaction details
    console.log("Contract deployment: BridgedERC20");
    console.log("Contract address:", bridgedERC20.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Wait half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    // Writing updated parameters back to the JSON file
    parsedData.bridgedERC20Address = bridgedERC20.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_19_bridged_erc20.js --network " + providerName + " " + bridgedERC20.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
