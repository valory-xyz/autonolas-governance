/*global process*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

async function main() {
    const initialMint = "1000000000000000000000000"; // 1000000
    const oneWeek = 7 * 86400;

    const OLAS = await ethers.getContractFactory("OLAS");
    const olas = await OLAS.deploy();
    await olas.deployed();

    const signers = await ethers.getSigners();
    const deployer = signers[0];
    await olas.mint(deployer.address, initialMint);

    // Read ABI from the JSON file
    const fs = require("fs");
    const veCRVJSON = "abis/test/veCRV.json";
    const contractFromJSON = fs.readFileSync(veCRVJSON, "utf8");
    const veCRVContract = JSON.parse(contractFromJSON);

    // Get the original Voting Escrow contract instance
    const veCRV = await ethers.getContractAt(veCRVContract, "0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2");
    const blockNumber = await ethers.provider.getBlockNumber("latest");
    console.log("block number after original VE deployment", blockNumber);
    const block = await ethers.provider.getBlock(blockNumber);
    console.log("block timestamp after original VE deployment", block.timestamp);

    // block number for the first transaction - 10655231, createLock(66500000000000000000, 1598578682), block.timestamp == 1597369454
    // unlockTime == 1598486400

    const VE = await ethers.getContractFactory("veOLAS");
    const ve = await VE.deploy(olas.address, "name", "symbol");
    await ve.deployed();

    // Change the token storage slot value from CRV to OLAS address
    const tokenSlot = "0x0";
    // Storage value must be a 32 bytes long padded with leading zeros hex string
    const value = ethers.utils.hexlify(ethers.utils.zeroPad(olas.address, 32));
    await ethers.provider.send("hardhat_setStorageAt", [veCRV.address, tokenSlot, value]);
    //console.log("veCRV token now", await veCRV.token());
    //console.log("OLAS address", olas.address);

    // Approve both ve tokens to a max amount
    await olas.approve(veCRV.address, ethers.constants.MaxUint256);
    await olas.approve(ve.address, ethers.constants.MaxUint256);


    // !!!!!!!!!!!!!!!!!!!!! CREATE LOCK !!!!!!!!!!!!!!!!!!!!!!!!!!
    let totalNumPoints = 1;
    let deployerNumPoints = 0;

    // Simulate veCRV first lock
    ethers.provider.send("evm_mine");
    let blockNumberBefore = await ethers.provider.getBlockNumber("latest");
    //console.log("block number before veCRV", blockNumberBefore);

    let tx1 = await veCRV.create_lock("66500000000000000000", "1598578682");
    let tx2 = await ve.createLock("66500000000000000000", "1216946");

    let blockNumberAfter = await ethers.provider.getBlockNumber("latest");
    //console.log("block number after ve", blockNumberAfter);
    ethers.provider.send("evm_mine");
    await tx1.wait();
    await tx2.wait();

    // Get the storage values
    let veCRVLockedBalance = await veCRV.locked(deployer.address);
    let veCRVUserPoint = await veCRV.user_point_history(deployer.address, deployerNumPoints + 1);
    let veCRVSupplyPoint = await veCRV.point_history(totalNumPoints);

    let veLockedBalance = await ve.mapLockedBalances(deployer.address);
    let veUserPoint = await ve.mapUserPoints(deployer.address, deployerNumPoints);
    let veSupplyPoint = await ve.mapSupplyPoints(totalNumPoints);

    // Compare results
    if (blockNumberAfter == blockNumberBefore) {
        console.log("Checking create lock");
        expect(veCRVLockedBalance.amount).to.equal(veLockedBalance.amount);
        expect(veCRVLockedBalance.end).to.equal(veLockedBalance.endTime);
        expect(veCRVUserPoint.bias).to.equal(veUserPoint.bias);
        expect(veCRVUserPoint.slope).to.equal(veUserPoint.slope);
        expect(veCRVUserPoint.ts).to.equal(veUserPoint.ts);
        expect(veCRVUserPoint.blk).to.equal(veUserPoint.blockNumber);
        expect(veCRVSupplyPoint.bias).to.equal(veSupplyPoint.bias);
        expect(veCRVSupplyPoint.slope).to.equal(veSupplyPoint.slope);
        expect(veCRVSupplyPoint.ts).to.equal(veSupplyPoint.ts);
        expect(veCRVSupplyPoint.blk).to.equal(veSupplyPoint.blockNumber);
    }


    // !!!!!!!!!!!!!!!!!!!!! INCREASE AMOUNT !!!!!!!!!!!!!!!!!!!!!!!!!!
    totalNumPoints += 1;
    deployerNumPoints += 1;

    // Increase amount
    ethers.provider.send("evm_mine");
    blockNumberBefore = await ethers.provider.getBlockNumber("latest");
    //console.log("block number before veCRV", blockNumberBefore);

    tx1 = await veCRV.increase_amount("66500000000000000000");
    tx2 = await ve.increaseAmount("66500000000000000000");

    blockNumberAfter = await ethers.provider.getBlockNumber("latest");
    //console.log("block number after ve", blockNumberAfter);
    ethers.provider.send("evm_mine");
    await tx1.wait();
    await tx2.wait();

    // Get the storage values
    veCRVLockedBalance = await veCRV.locked(deployer.address);
    veCRVUserPoint = await veCRV.user_point_history(deployer.address, deployerNumPoints + 1);
    veCRVSupplyPoint = await veCRV.point_history(totalNumPoints);

    veLockedBalance = await ve.mapLockedBalances(deployer.address);
    veUserPoint = await ve.mapUserPoints(deployer.address, deployerNumPoints);
    veSupplyPoint = await ve.mapSupplyPoints(totalNumPoints);

    // Compare results
    if (blockNumberAfter == blockNumberBefore) {
        console.log("Checking increase amount");
        expect(veCRVLockedBalance.amount).to.equal(veLockedBalance.amount);
        expect(veCRVLockedBalance.end).to.equal(veLockedBalance.endTime);
        expect(veCRVUserPoint.bias).to.equal(veUserPoint.bias);
        expect(veCRVUserPoint.slope).to.equal(veUserPoint.slope);
        expect(veCRVUserPoint.ts).to.equal(veUserPoint.ts);
        expect(veCRVUserPoint.blk).to.equal(veUserPoint.blockNumber);
        expect(veCRVSupplyPoint.bias).to.equal(veSupplyPoint.bias);
        expect(veCRVSupplyPoint.slope).to.equal(veSupplyPoint.slope);
        expect(veCRVSupplyPoint.ts).to.equal(veSupplyPoint.ts);
        expect(veCRVSupplyPoint.blk).to.equal(veSupplyPoint.blockNumber);
    }


    // !!!!!!!!!!!!!!!!!!!!! INCREASE UNLOCK TIME !!!!!!!!!!!!!!!!!!!!!!!!!!
    totalNumPoints += 1;
    deployerNumPoints += 1;

    // Increase unlock time
    ethers.provider.send("evm_mine");
    blockNumberBefore = await ethers.provider.getBlockNumber("latest");
    //console.log("block number before veCRV", blockNumberBefore);

    tx1 = await veCRV.increase_unlock_time("1600393082");
    tx2 = await ve.increaseUnlockTime(6 * oneWeek);

    blockNumberAfter = await ethers.provider.getBlockNumber("latest");
    //console.log("block number after ve", blockNumberAfter);
    ethers.provider.send("evm_mine");
    await tx1.wait();
    await tx2.wait();

    // Get the storage values
    veCRVLockedBalance = await veCRV.locked(deployer.address);
    veCRVUserPoint = await veCRV.user_point_history(deployer.address, deployerNumPoints + 1);
    veCRVSupplyPoint = await veCRV.point_history(totalNumPoints);

    veLockedBalance = await ve.mapLockedBalances(deployer.address);
    veUserPoint = await ve.mapUserPoints(deployer.address, deployerNumPoints);
    veSupplyPoint = await ve.mapSupplyPoints(totalNumPoints);

    // Compare results
    if (blockNumberAfter == blockNumberBefore) {
        console.log("Checking increase unlock time");
        expect(veCRVLockedBalance.amount).to.equal(veLockedBalance.amount);
        expect(veCRVLockedBalance.end).to.equal(veLockedBalance.endTime);
        expect(veCRVUserPoint.bias).to.equal(veUserPoint.bias);
        expect(veCRVUserPoint.slope).to.equal(veUserPoint.slope);
        expect(veCRVUserPoint.ts).to.equal(veUserPoint.ts);
        expect(veCRVUserPoint.blk).to.equal(veUserPoint.blockNumber);
        expect(veCRVSupplyPoint.bias).to.equal(veSupplyPoint.bias);
        expect(veCRVSupplyPoint.slope).to.equal(veSupplyPoint.slope);
        expect(veCRVSupplyPoint.ts).to.equal(veSupplyPoint.ts);
        expect(veCRVSupplyPoint.blk).to.equal(veSupplyPoint.blockNumber);
    }


    // !!!!!!!!!!!!!!!!!!!!! WITHDRAW !!!!!!!!!!!!!!!!!!!!!!!!!!
    totalNumPoints += 1;
    deployerNumPoints += 1;

    // Move pass the time of unlock
    ethers.provider.send("evm_increaseTime", [7 * oneWeek]);
    ethers.provider.send("evm_mine");
    ethers.provider.send("evm_mine");
    blockNumberBefore = await ethers.provider.getBlockNumber("latest");
    //    console.log("block number before veCRV", blockNumberBefore);

    tx1 = await veCRV.withdraw();
    tx2 = await ve.withdraw();

    blockNumberAfter = await ethers.provider.getBlockNumber("latest");
    //    console.log("block number after ve", blockNumberAfter);
    ethers.provider.send("evm_mine");
    await tx1.wait();
    await tx2.wait();

    // Get the storage values
    veCRVLockedBalance = await veCRV.locked(deployer.address);
    veCRVUserPoint = await veCRV.user_point_history(deployer.address, deployerNumPoints + 1);
    let numLastSupplyPoint = await veCRV.epoch();
    veCRVSupplyPoint = await veCRV.point_history(numLastSupplyPoint);

    veLockedBalance = await ve.mapLockedBalances(deployer.address);
    veUserPoint = await ve.mapUserPoints(deployer.address, deployerNumPoints);
    veSupplyPoint = await ve.mapSupplyPoints(numLastSupplyPoint);

    // Compare results
    if (blockNumberAfter == blockNumberBefore) {
        console.log("Checking withdraw");
        expect(veCRVLockedBalance.amount).to.equal(veLockedBalance.amount);
        expect(veCRVLockedBalance.end).to.equal(veLockedBalance.endTime);
        expect(veCRVUserPoint.bias).to.equal(veUserPoint.bias);
        expect(veCRVUserPoint.slope).to.equal(veUserPoint.slope);
        expect(veCRVUserPoint.ts).to.equal(veUserPoint.ts);
        expect(veCRVUserPoint.blk).to.equal(veUserPoint.blockNumber);
        expect(veCRVSupplyPoint.bias).to.equal(veSupplyPoint.bias);
        expect(veCRVSupplyPoint.slope).to.equal(veSupplyPoint.slope);
        expect(veCRVSupplyPoint.ts).to.equal(veSupplyPoint.ts);
        expect(veCRVSupplyPoint.blk).to.equal(veSupplyPoint.blockNumber);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
