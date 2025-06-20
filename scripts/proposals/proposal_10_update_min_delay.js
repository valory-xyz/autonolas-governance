/*global process*/

const { ethers } = require("hardhat");
const safeContracts = require("@gnosis.pm/safe-contracts");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    const parsedData = JSON.parse(dataFromJSON);

    const timelockAddress = parsedData.timelockAddress;
    const timelock = await ethers.getContractAt("Timelock", timelockAddress);

    console.log("Change minDelay parameter for Timelock");
    const targets = [timelock.address];
    const values = new Array(1).fill(0);
    const callDatas = [
        timelock.interface.encodeFunctionData("updateDelay", [0])
    ];
    const description = "Timelock to change minDealay to zero";

    // Proposal details
    console.log("targets:", targets);
    console.log("values:", values);
    console.log("call datas:", callDatas);
    console.log("description:", description);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
