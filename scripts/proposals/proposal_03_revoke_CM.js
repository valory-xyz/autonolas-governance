/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);

    const proposerRole = ethers.utils.id("PROPOSER_ROLE");
    const executorRole = ethers.utils.id("EXECUTOR_ROLE");
    const cancellerRole = ethers.utils.id("CANCELLER_ROLE");

    const timelockAddress = parsedData.timelockAddress;
    const CMAddress = parsedData.CM;

    // Obtaining proposal values
    console.log("3. Revoking CM in the Timelock");
    const timelock = await ethers.getContractAt("Timelock", timelockAddress);
    const targets = new Array(3).fill(timelockAddress);
    const values = new Array(3).fill(0);
    const callDatas = [
        timelock.interface.encodeFunctionData("revokeRole", [executorRole, CMAddress]),
        timelock.interface.encodeFunctionData("revokeRole", [proposerRole, CMAddress]),
        timelock.interface.encodeFunctionData("revokeRole", [cancellerRole, CMAddress]),
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