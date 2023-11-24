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
    console.log("3. EOA to deploy ERC20 child tunnel contract");
    const FxERC20ChildTunnel = await ethers.getContractFactory("FxERC20ChildTunnel");
    console.log("You are signing the following transaction: FxERC20ChildTunnel.connect(EOA).deploy(fxChild, childToken, rootToken)");
    const gasPriceInGwei = "230";
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");
    const fxERC20ChildTunnel = await FxERC20ChildTunnel.connect(EOA).deploy(parsedData.fxChildAddress, parsedData.childTokenAddress, parsedData.bridgedERC20Address, { gasPrice });
    const result = await fxERC20ChildTunnel.deployed();

    // Transaction details
    console.log("Contract deployment: FxERC20ChildTunnel");
    console.log("Contract address:", fxERC20ChildTunnel.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Wait half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    // Writing updated parameters back to the JSON file
    parsedData.fxERC20ChildTunnelAddress = fxERC20ChildTunnel.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/bridges/polygon/verify_03_erc20_child_tunnel.js --network " + providerName + " " + fxERC20ChildTunnel.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
