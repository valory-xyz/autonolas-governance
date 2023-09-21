/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);

    const cancellerRole = ethers.utils.id("CANCELLER_ROLE");
    const timelockAddress = parsedData.timelockAddress;
    const treasuryAddress = parsedData.treasuryAddress;
    const depositoryAddress = parsedData.depositoryAddress;
    const serviceRegistryTokenUtilityAddress = parsedData.serviceRegistryTokenUtilityAddress;
    const guardCMAddress = parsedData.guardCMAddress;
    const CMAddress = parsedData.CM;

    // Obtaining proposal values
    console.log("Revoking cancellor role of CM in the Timelock and enabling selectors");
    const timelock = await ethers.getContractAt("Timelock", timelockAddress);
    const guardCM = await ethers.getContractAt("GuardCM", guardCMAddress);
    const targets = [guardCMAddress, timelockAddress];
    const values = new Array(2).fill(0);
    const callDatas = [
        guardCM.interface.encodeFunctionData("setTargetSelectors", [[treasuryAddress, treasuryAddress, depositoryAddress, serviceRegistryTokenUtilityAddress], [0x8456cb59, 0x8f202bf9, 0x58d3ec6a, 0xece53132], [true, true, true, true]]),
        timelock.interface.encodeFunctionData("revokeRole", [cancellerRole, CMAddress])
    ];
    const description = "Timelock to revoke CM roles";

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
