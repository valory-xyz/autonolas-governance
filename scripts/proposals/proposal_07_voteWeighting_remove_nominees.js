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
    const targets = Array(7).fill(voteWeightingAddress);
    const values = Array(targets.length).fill(0);
    const callDatas = [
        // MemeCelo Alpha
        //vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "f39cd0eE4C502Df7D26F28cFAdd579724A3CFCe8", 42220]),
        // MemeBase Alpha
        //vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "06702a05312091013fdb50c8b60b98ca30762931", 8453]),
        // Incorrect QS Expert 13
        //vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "aeb8bf3613cb1c988f58e97297b38890609044ee", 100]),
        // Incorrect QS Expert 14
        //vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "ab21bce7ae5443fcbfaf29a4e2b9b398f510f9e9", 100]),

        // Contribute Alpha I
        //vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "95146adf659f455f300d7521b3b62a3b6c4aba1f", 8453]),
        // Contribute Alpha II
        //vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "2c8a5ac7b431ce04a037747519ba475884bce2fb", 8453]),
        // Contribute Alpha III
        //vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "708e511d5fcb3bd5a5d42f42aa9a69ec5b0ee2e8", 8453])

        // Optimus Alpha Optimism
        vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "88996bbde7f982d93214881756840ce2c77c4992", 10]),
        // Optimus Alpha Mode
        vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "5fc25f50e96857373c64dc0edb1abcbed4587e91", 34443]),
        // MemeBase Alpha II
        vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "c653622fd75026a020995a1d8c8651316cbbc4da", 8453]),
        // MemeCelo Alpha II
        vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "95d12d193d466237bc1e92a1a7756e4264f574ab", 42220]),
        // MemeBase Beta I
        vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "6011e09e7c095e76980b22498d69df18eb62bed8", 8453]),
        // MemeBase Beta II
        vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "fb7669c3adf673b3a545fa5acd987dbfda805e22", 8453]),
        // MemeBase Beta III
        vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "ca61633b03c54f64b6a7f1f9a9c0a6feb231cc4d", 8453])

        // TBD
        // Quickstart Beta - Hobbyist
        //vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "389b46c259631acd6a69bde8b6cee218230bae8c", 100]),
        // Quickstart Beta - Hobbyist 2
        //vw.interface.encodeFunctionData("removeNominee", ["0x" + "0".repeat(24) + "238eb6993b90a978ec6aad7530d6429c949c08da", 100]),
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
