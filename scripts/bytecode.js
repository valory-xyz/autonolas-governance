/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const artifact = require("../artifacts/contracts/OLAS.sol/OLAS.json");
    console.log("############ BYTE CODE ############");
    console.log(artifact.bytecode);
    const initCodeHash = ethers.utils.keccak256(artifact.bytecode);
    console.log("############ BYTE CODE HASH ############");
    console.log(initCodeHash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });