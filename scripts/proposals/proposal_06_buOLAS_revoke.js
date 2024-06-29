/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);

    const signers = await ethers.getSigners();

    // EOA address
    const EOA = signers[0];

    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    // Get all the necessary contract addresses
    const buOLASAddress = parsedData.buOLASAddress;

    // Get the contracts
    const bu = await ethers.getContractAt("buOLAS", buOLASAddress);

    // Proposal preparation
    console.log("Revoking from buOLAS");
    // Modify the address to the required one
    const revokeAddress = signers[1].address;
    const targets = [buOLASAddress];
    const values = [0];
    const callDatas = [bu.interface.encodeFunctionData("revoke", [[revokeAddress]])];

    // Proposal details
    console.log("targets:", targets);
    console.log("values:", values);
    console.log("call datas:", callDatas);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
