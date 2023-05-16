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

    let provider;
    if (providerName == "polygon") {
        provider = await ethers.providers.getDefaultProvider("matic");
    } else {
        const mumbaiURL = "https://polygon-mumbai.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MUMBAI;
        provider = new ethers.providers.JsonRpcProvider(mumbaiURL);
    }
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
    console.log("1. EOA to deploy governor tunnel contract");
    const FxGovernorTunnel = await ethers.getContractFactory("FxGovernorTunnel");
    console.log("You are signing the following transaction: FxGovernorTunnel.connect(EOA).deploy(fxChild, timelock)");
    const gasPriceInGwei = "230";
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");
    const fxGovernorTunnel = await FxGovernorTunnel.connect(EOA).deploy(parsedData.fxChildAddress, parsedData.timelockAddress, { gasPrice });
    const result = await fxGovernorTunnel.deployed();

    // Transaction details
    console.log("Contract deployment: FxGovernorTunnel");
    console.log("Contract address:", fxGovernorTunnel.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Writing updated parameters back to the JSON file
    parsedData.fxGovernorTunnelAddress = fxGovernorTunnel.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/bridges/polygon/verify_01_governor_tunnel.js --network " + providerName + " " + fxGovernorTunnel.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
