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
    const fxERC20ChildTunnelAddress = parsedData.fxERC20ChildTunnelAddress;
    const fxERC20RootTunnelAddress = parsedData.fxERC20RootTunnelAddress;
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
    console.log("4. FxERC20ChildTunnel to set root tunnel to FxERC20RootTunnel");
    const fxERC20ChildTunnel = await ethers.getContractAt("FxERC20ChildTunnel", fxERC20ChildTunnelAddress);
    console.log("You are signing the following transaction: FxERC20ChildTunnel.connect(EOA).setFxRootTunnel(FxERC20RootTunnel)");
    const gasPriceInGwei = "110";
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");
    const result = await fxERC20ChildTunnel.connect(EOA).setFxRootTunnel(fxERC20RootTunnelAddress, { gasPrice });

    // Transaction details
    console.log("Contract deployment: FxERC20ChildTunnel");
    console.log("Contract address:", fxERC20ChildTunnel.address);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
