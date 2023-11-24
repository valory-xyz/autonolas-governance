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
    console.log("20. EOA to deploy ERC20 root tunnel contract");
    const FxERC20RootTunnel = await ethers.getContractFactory("FxERC20RootTunnel");
    console.log("You are signing the following transaction: FxERC20RootTunnel.connect(EOA).deploy(checkpointManager, fxRoot, childToken, rootToken)");
    const fxERC20RootTunnel = await FxERC20RootTunnel.connect(EOA).deploy(parsedData.checkpointManagerAddress,
        parsedData.fxRootAddress, parsedData.childTokenAddress, parsedData.bridgedERC20Address);
    const result = await fxERC20RootTunnel.deployed();

    // Transaction details
    console.log("Contract deployment: FxERC20RootTunnel");
    console.log("Contract address:", fxERC20RootTunnel.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Wait half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    // Writing updated parameters back to the JSON file
    parsedData.fxERC20RootTunnelAddress = fxERC20RootTunnel.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_20_erc20_root_tunnel.js --network " + providerName + " " + fxERC20RootTunnel.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
