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
    const gasPriceInGwei = parsedData.gasPriceInGwei;

    const networkURL = parsedData.networkURL;
    const provider = new ethers.providers.JsonRpcProvider(networkURL);
    const signers = await ethers.getSigners();

    let EOA;
    if (useLedger) {
        EOA = new LedgerSigner(provider, derivationPath);
    } else {
        EOA = signers[0];
    }
    // EOA address
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    // Transaction signing and execution
    console.log("1. EOA to deploy home mediator contract");
    const WormholeMessenger = await ethers.getContractFactory("WormholeMessenger");
    console.log("You are signing the following transaction: WormholeMessenger.connect(EOA).deploy(L2WormholeRelayerAddress, timelockAddress)");
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");
    const wormholeMessenger = await WormholeMessenger.connect(EOA).deploy(parsedData.L2WormholeRelayerAddress, parsedData.timelockAddress, { gasPrice });
    const result = await wormholeMessenger.deployed();

    // Transaction details
    console.log("Contract deployment: WormholeMessenger");
    console.log("Contract address:", wormholeMessenger.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Writing updated parameters back to the JSON file
    parsedData.wormholeMessengerAddress = wormholeMessenger.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/bridges/celo/verify_01_home_mediator.js --network " + providerName + " " + wormholeMessenger.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
