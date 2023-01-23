/*global process*/

const { ethers } = require("hardhat");
const oneDay = 86400;
const oneWeek = 7 * oneDay;

async function main() {
    let block = await ethers.provider.getBlock("latest");
    console.log("block before is:", block.number);
    console.log("timestamp before is:", block.timestamp);
    // Move time to more than a week and a number of blocks as a number of days
    for (let i = 0; i <= oneWeek; i += oneDay) {
        ethers.provider.send("evm_increaseTime", [oneDay]);
        ethers.provider.send("evm_mine");
    }
    block = await ethers.provider.getBlock("latest");
    console.log("block after is:", block.number);
    console.log("timestamp after is:", block.timestamp);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });