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
    const fxERC20RootTunnelAddress = parsedData.fxERC20RootTunnelAddress;
    const bridgedERC20Address = parsedData.bridgedERC20Address;
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
    console.log("21. EOA to change owner of BridgedERC20 to FxERC20RootTunnel");
    const bridgedERC20 = await ethers.getContractAt("BridgedERC20", bridgedERC20Address);
    console.log("You are signing the following transaction: bridgedERC20.connect(EOA).changeOwner(FxERC20RootTunnel)");
    const result = await bridgedERC20.changeOwner(fxERC20RootTunnelAddress);

    // Transaction details
    console.log("Contract deployment: BridgedERC20");
    console.log("Contract address:", bridgedERC20.address);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
