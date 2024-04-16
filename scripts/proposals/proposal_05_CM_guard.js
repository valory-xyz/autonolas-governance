/*global process*/

const { ethers } = require("hardhat");
const safeContracts = require("@gnosis.pm/safe-contracts");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    const parsedData = JSON.parse(dataFromJSON);

    // Get the multisig
    const multisig = await ethers.getContractAt("GnosisSafe", parsedData.CM);
    const nonce = await multisig.nonce();

    const guardCMAddress = parsedData.guardCMAddress;

    // Construct the payload for the multisig to swap the guard by the Timelock
    const txHashData = await safeContracts.buildContractCall(multisig, "setGuard", [guardCMAddress], nonce, 0, 0);

    console.log("Set new guard via Timelock Module");
    const targets = [multisig.address];
    const values = new Array(1).fill(0);
    const callDatas = [
        multisig.interface.encodeFunctionData("execTransactionFromModule", [txHashData.to, 0, txHashData.data, txHashData.operation])
    ];
    const description = "Timelock to change guard via module and select selects";

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
