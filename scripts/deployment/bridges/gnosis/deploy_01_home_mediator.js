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
    let EOA;

    let networkURL;
    if (providerName === "gnosis") {
        if (!process.env.GNOSIS_CHAIN_API_KEY) {
            console.log("set GNOSIS_CHAIN_API_KEY env variable");
            return;
        }
        networkURL = "https://rpc.gnosischain.com";
    } else if (providerName === "chiado") {
        networkURL = "https://rpc.chiadochain.net";
    } else {
        console.log("Unknown network provider", providerName);
        return;
    }

    const provider = new ethers.providers.JsonRpcProvider(networkURL);
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
    console.log("1. EOA to deploy home mediator contract");
    const HomeMediator = await ethers.getContractFactory("HomeMediator");
    console.log("You are signing the following transaction: HomeMediator.connect(EOA).deploy(AMBContractProxyHomeAddress, timelockAddress)");
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");
    const homeMediator = await HomeMediator.connect(EOA).deploy(parsedData.AMBContractProxyHomeAddress, parsedData.timelockAddress, { gasPrice });
    const result = await homeMediator.deployed();

    // Transaction details
    console.log("Contract deployment: HomeMediator");
    console.log("Contract address:", homeMediator.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Writing updated parameters back to the JSON file
    parsedData.homeMediatorAddress = homeMediator.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/bridges/gnosis/verify_01_home_mediator.js --network " + providerName + " " + homeMediator.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
