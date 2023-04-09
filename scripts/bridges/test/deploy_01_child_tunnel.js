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

    const mumbaiURL = "https://polygon-mumbai.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MUMBAI;
    const provider = new ethers.providers.JsonRpcProvider(mumbaiURL);
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
    console.log("1. EOA to deploy child tunnel contract");
    const FxChildTunnel = await ethers.getContractFactory("FxChildTunnel");
    console.log("You are signing the following transaction: FxChildTunnel.connect(EOA).deploy(fxChildAddress)");
    const fxChildTunnel = await FxChildTunnel.connect(EOA).deploy(parsedData.fxChildAddress);
    const result = await fxChildTunnel.deployed();

    // Transaction details
    console.log("Contract deployment: FxChildTunnel");
    console.log("Contract address:", fxChildTunnel.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Writing updated parameters back to the JSON file
    parsedData.fxChildTunnelAddress = fxChildTunnel.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/bridges/verify_01_child_tunnel.js --network " + providerName + " " + fxChildTunnel.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
