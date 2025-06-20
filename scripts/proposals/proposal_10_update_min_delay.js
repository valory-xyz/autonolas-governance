/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    const parsedData = JSON.parse(dataFromJSON);
    const HashZero = ethers.constants.HashZero;

    const timelockAddress = parsedData.timelockAddress;
    const timelock = await ethers.getContractAt("Timelock", timelockAddress);

    let timelockPayload = timelock.interface.encodeFunctionData("updateDelay", [0]);

    console.log("Change minDelay parameter for Timelock");
    const targets = [timelockAddress];
    const values = new Array(1).fill(0);
    const callDatas = [timelockPayload];
    const description = "Timelock to change minDealay to zero";

    // Proposal details
    console.log("targets:", targets);
    console.log("values:", values);
    console.log("call datas:", callDatas);
    console.log("description:", description);

    // Set a new minDelay = 1 day
    timelockPayload = timelock.interface.encodeFunctionData("updateDelay", [86400]);

    // Schedule and execute by a CM
    const schedulePayload = timelock.interface.encodeFunctionData("schedule", [timelockAddress, 0, timelockPayload,
        HashZero, HashZero, 0]);
    const executePayload = timelock.interface.encodeFunctionData("execute", [timelockAddress, 0, timelockPayload,
        HashZero, HashZero]);

    console.log("CM schedule:", schedulePayload);
    console.log("CM execute:", executePayload);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
