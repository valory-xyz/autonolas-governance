/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);

    const adminRole = ethers.utils.id("TIMELOCK_ADMIN_ROLE");
    const proposerRole = ethers.utils.id("PROPOSER_ROLE");
    const executorRole = ethers.utils.id("EXECUTOR_ROLE");
    const cancellerRole = ethers.utils.id("CANCELLER_ROLE");

    const timelockAddress = parsedData.timelockAddress;
    const governorAddress = parsedData.governorAddress;
    const governorTwoAddress = parsedData.governorTwoAddress;

    // Obtaining proposal values
    console.log("2. Revoking governorOLAS roles and granting governorTwoOLAS roles in the Timelock");
    const timelock = await ethers.getContractAt("Timelock", timelockAddress);
    const targets = new Array(8).fill(timelockAddress);
    const values = new Array(8).fill(0);
    const callDatas = [
        timelock.interface.encodeFunctionData("revokeRole", [adminRole, governorAddress]),
        timelock.interface.encodeFunctionData("revokeRole", [executorRole, governorAddress]),
        timelock.interface.encodeFunctionData("revokeRole", [proposerRole, governorAddress]),
        timelock.interface.encodeFunctionData("revokeRole", [cancellerRole, governorAddress]),
        timelock.interface.encodeFunctionData("grantRole", [adminRole, governorTwoAddress]),
        timelock.interface.encodeFunctionData("grantRole", [executorRole, governorTwoAddress]),
        timelock.interface.encodeFunctionData("grantRole", [proposerRole, governorTwoAddress]),
        timelock.interface.encodeFunctionData("grantRole", [cancellerRole, governorTwoAddress])
    ];
    const description = "Timelock to revoke original GovernorOLAS roles and grant new GovernorOLAS roles";

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