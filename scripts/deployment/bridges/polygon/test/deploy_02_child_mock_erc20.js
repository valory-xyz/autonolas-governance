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
    const providerName = "polygonMumbai";
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
    console.log("2. EOA to deploy child mock ERC20 contract and change its owner to the FxGovernorTunnel");
    const ChildMockERC20 = await ethers.getContractFactory("ChildMockERC20");
    console.log("You are signing the following transaction: ChildMockERC20.connect(EOA).deploy()");
    const childMockERC20 = await ChildMockERC20.connect(EOA).deploy();
    let result = await childMockERC20.deployed();

    // Transaction details
    console.log("Contract deployment: ChildMockERC20");
    console.log("Contract address:", childMockERC20.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Writing updated parameters back to the JSON file
    parsedData.childMockERC20Address = childMockERC20.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Change the owner of the contract
    result = await childMockERC20.changeOwner(parsedData.fxGovernorTunnelAddress);
    console.log("Transaction:", result.hash);

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --network " + providerName + " " + childMockERC20.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
