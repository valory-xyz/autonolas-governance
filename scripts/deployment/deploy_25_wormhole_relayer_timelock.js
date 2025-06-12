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
    console.log("25. EOA to deploy WormholeRelayerTimelock contract");
    const WormholeRelayerTimelock = await ethers.getContractFactory("WormholeRelayerTimelock");
    console.log("You are signing the following transaction: WormholeRelayerTimelock.connect(EOA).deploy(OLAS)");
    const wormholeRelayerTimelock = await WormholeRelayerTimelock.connect(EOA).deploy(parsedData.wormholeL1MessageRelayerAddress);
    const result = await wormholeRelayerTimelock.deployed();

    // Transaction details
    console.log("Contract deployment: wormholeRelayerTimelock");
    console.log("Contract address:", wormholeRelayerTimelock.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // If on sepolia, wait half a minute for the transaction completion
    if (providerName === "sepolia") {
        await new Promise(r => setTimeout(r, 30000));
    }

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_25_wormhole_relayer_timelock.js --network " + providerName + " " + wormholeRelayerTimelock.address, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.wormholeRelayerTimelockAddress = wormholeRelayerTimelock.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });