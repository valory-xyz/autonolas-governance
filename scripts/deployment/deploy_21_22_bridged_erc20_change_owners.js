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
    const bridgedERC20Address = parsedData.bridgedERC20Address;
    const fxERC20ChildTunnelAddress = parsedData.fxERC20ChildTunnelAddress;
    const fxERC20RootTunnelAddress = parsedData.fxERC20RootTunnelAddress;
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
    let result = await bridgedERC20.connect(EOA).changeOwner(fxERC20RootTunnelAddress);

    // Transaction details
    console.log("Contract deployment: BridgedERC20");
    console.log("Contract address:", bridgedERC20.address);
    console.log("Transaction:", result.hash);

    console.log("22. FxERC20RootTunnel to set child tunnel to FxERC20ChildTunnel");
    const fxERC20RootTunnel = await ethers.getContractAt("FxERC20RootTunnel", fxERC20RootTunnelAddress);
    console.log("You are signing the following transaction: fxERC20RootTunnel.connect(EOA).setFxChildTunnel(FxERC20ChildTunnel)");
    result = await fxERC20RootTunnel.connect(EOA).setFxChildTunnel(fxERC20ChildTunnelAddress);

    // Transaction details
    console.log("Contract deployment: FxERC20RootTunnel");
    console.log("Contract address:", fxERC20RootTunnel.address);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
