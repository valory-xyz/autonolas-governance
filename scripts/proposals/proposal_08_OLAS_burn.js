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
    const olasAddress = parsedData.olasAddress;

    // Get the contracts
    const olas = await ethers.getContractAt("OLAS", olasAddress);

    // Proposal preparation
    console.log("Burn from OLAS");
    // Modify the address to the required one
    const amount = "25239360700691267422933902";
    const targets = [olasAddress];
    const values = [0];
    const callDatas = [olas.interface.encodeFunctionData("burn", [amount])];

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
