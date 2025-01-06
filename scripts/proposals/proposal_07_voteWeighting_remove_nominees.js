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
    const voteWeightingAddress = parsedData.voteWeightingAddress;

    // Get the contracts
    const vw = await ethers.getContractAt("VoteWeighting", voteWeightingAddress);

    // Proposal preparation
    console.log("Remove nominees from VoteWeighting");
    // Modify the address to the required one
    const targets = [voteWeightingAddress, voteWeightingAddress];
    const values = Array(targets.length).fill(0);
    const callDatas = [
        // Quickstart Beta - Hobbyist
        //vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "389b46c259631acd6a69bde8b6cee218230bae8c", 100]),
        // Quickstart Beta - Hobbyist 2
        //vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "238eb6993b90a978ec6aad7530d6429c949c08da", 100]),
        // MemeCelo Alpha
        //vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "f39cd0eE4C502Df7D26F28cFAdd579724A3CFCe8", 42220]),
        // MemeBase Alpha
        //vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "06702a05312091013fdb50c8b60b98ca30762931", 8453]),
        // Incorrect QS Expert 13
        vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "aeb8bf3613cb1c988f58e97297b38890609044ee", 100]),
        // MemeBase Alpha
        vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "ab21bce7ae5443fcbfaf29a4e2b9b398f510f9e9", 100])
    ];

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
