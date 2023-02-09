/*global process*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

async function main() {
    const initialMint = "1000000000000000000000000"; // 1000000
    const oneWeek = 7 * 86400;
    const oneOLASBalance = ethers.utils.parseEther("100");
    const twoOLASBalance = ethers.utils.parseEther("200");
    const threeOLASBalance = ethers.utils.parseEther("300");
    const fiveOLASBalance = ethers.utils.parseEther("500");

    const OLAS = await ethers.getContractFactory("OLAS");
    const olas = await OLAS.deploy();
    await olas.deployed();

    const signers = await ethers.getSigners();
    const deployer = signers[0];
    const user = signers[1];
    const accounts = [deployer.address, user.address];
    for (let i = 0; i < accounts.length; i++) {
        await olas.mint(accounts[i], initialMint);
    }

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
    await olas.connect(user).approve(veCRV.address, ethers.constants.MaxUint256);
    await olas.approve(ve.address, ethers.constants.MaxUint256);
    await olas.connect(user).approve(ve.address, ethers.constants.MaxUint256);


    // !!!!!!!!!!!!!!!!!!!!! CREATE LOCK !!!!!!!!!!!!!!!!!!!!!!!!!!
    let totalNumPoints = 0;
    let accountNumPoints = 0;

    // Simulate veCRV first lock
    ethers.provider.send("evm_mine");
    let blockNumberBefore1 = await ethers.provider.getBlockNumber("latest");
    //console.log("block number before veCRV", blockNumberBefore);

    let tx1 = await veCRV.create_lock(oneOLASBalance, "1598578682");
    let tx2 = await ve.createLock(oneOLASBalance, 3 * oneWeek);
    let blockNumberAfter1 = await ethers.provider.getBlockNumber("latest");
    //console.log("block number after ve", blockNumberAfter);
    ethers.provider.send("evm_mine");
    await tx1.wait();
    await tx2.wait();
    ethers.provider.send("evm_mine");
    let blockNumberBefore2 = await ethers.provider.getBlockNumber("latest");
    //console.log("block number before veCRV", blockNumberBefore);

    tx1 = await veCRV.connect(user).create_lock(twoOLASBalance, "1600393082");
    tx2 = await ve.connect(user).createLock(twoOLASBalance, 6 * oneWeek);

    let blockNumberAfter2 = await ethers.provider.getBlockNumber("latest");
    //console.log("block number after ve", blockNumberAfter);
    ethers.provider.send("evm_mine");
    await tx1.wait();
    await tx2.wait();

    // Get the storage values
    if (blockNumberAfter1 == blockNumberBefore1 && blockNumberAfter2 == blockNumberBefore2) {
        console.log("Checking create lock");
        for (let i = 0; i < accounts.length; i++) {
            let veCRVLockedBalance = await veCRV.locked(accounts[i]);
            let veCRVUserPoint = await veCRV.user_point_history(accounts[i], accountNumPoints + 1);

            let veLockedBalance = await ve.mapLockedBalances(accounts[i]);
            let veUserPoint = await ve.mapUserPoints(accounts[i], accountNumPoints);

            // Compare results
            expect(veCRVLockedBalance.amount).to.equal(veLockedBalance.amount);
            expect(veCRVLockedBalance.end).to.equal(veLockedBalance.endTime);
            expect(veCRVUserPoint.bias).to.equal(veUserPoint.bias);
            expect(veCRVUserPoint.slope).to.equal(veUserPoint.slope);
            expect(veCRVUserPoint.ts).to.equal(veUserPoint.ts);
            expect(veCRVUserPoint.blk).to.equal(veUserPoint.blockNumber);

            totalNumPoints += 1;
            let veCRVSupplyPoint = await veCRV.point_history(totalNumPoints);
            let veSupplyPoint = await ve.mapSupplyPoints(totalNumPoints);
            expect(veCRVSupplyPoint.bias).to.equal(veSupplyPoint.bias);
            expect(veCRVSupplyPoint.slope).to.equal(veSupplyPoint.slope);
            expect(veCRVSupplyPoint.ts).to.equal(veSupplyPoint.ts);
            expect(veCRVSupplyPoint.blk).to.equal(veSupplyPoint.blockNumber);
        }
    }


    // !!!!!!!!!!!!!!!!!!!!! INCREASE AMOUNT !!!!!!!!!!!!!!!!!!!!!!!!!!
    accountNumPoints += 1;

    // Increase amount
    ethers.provider.send("evm_mine");
    blockNumberBefore1 = await ethers.provider.getBlockNumber("latest");
    //console.log("block number before veCRV", blockNumberBefore);

    tx1 = await veCRV.increase_amount(threeOLASBalance);
    tx2 = await ve.increaseAmount(threeOLASBalance);

    blockNumberAfter1 = await ethers.provider.getBlockNumber("latest");
    //console.log("block number after ve", blockNumberAfter);
    ethers.provider.send("evm_mine");
    await tx1.wait();
    await tx2.wait();
    ethers.provider.send("evm_mine");
    blockNumberBefore2 = await ethers.provider.getBlockNumber("latest");
    //console.log("block number before veCRV", blockNumberBefore);

    tx1 = await veCRV.connect(user).increase_amount(fiveOLASBalance);
    tx2 = await ve.connect(user).increaseAmount(fiveOLASBalance);

    blockNumberAfter2 = await ethers.provider.getBlockNumber("latest");
    //console.log("block number after ve", blockNumberAfter);
    ethers.provider.send("evm_mine");
    await tx1.wait();
    await tx2.wait();

    // Get the storage values
    if (blockNumberAfter1 == blockNumberBefore1 && blockNumberAfter2 == blockNumberBefore2) {
        console.log("Checking increase amount");
        for (let i = 0; i < accounts.length; i++) {
            let veCRVLockedBalance = await veCRV.locked(accounts[i]);
            let veCRVUserPoint = await veCRV.user_point_history(accounts[i], accountNumPoints + 1);

            let veLockedBalance = await ve.mapLockedBalances(accounts[i]);
            let veUserPoint = await ve.mapUserPoints(accounts[i], accountNumPoints);

            // Compare results
            expect(veCRVLockedBalance.amount).to.equal(veLockedBalance.amount);
            expect(veCRVLockedBalance.end).to.equal(veLockedBalance.endTime);
            expect(veCRVUserPoint.bias).to.equal(veUserPoint.bias);
            expect(veCRVUserPoint.slope).to.equal(veUserPoint.slope);
            expect(veCRVUserPoint.ts).to.equal(veUserPoint.ts);
            expect(veCRVUserPoint.blk).to.equal(veUserPoint.blockNumber);

            totalNumPoints += 1;
            let veCRVSupplyPoint = await veCRV.point_history(totalNumPoints);
            let veSupplyPoint = await ve.mapSupplyPoints(totalNumPoints);
            expect(veCRVSupplyPoint.bias).to.equal(veSupplyPoint.bias);
            expect(veCRVSupplyPoint.slope).to.equal(veSupplyPoint.slope);
            expect(veCRVSupplyPoint.ts).to.equal(veSupplyPoint.ts);
            expect(veCRVSupplyPoint.blk).to.equal(veSupplyPoint.blockNumber);
        }
    }


    // !!!!!!!!!!!!!!!!!!!!! INCREASE UNLOCK TIME !!!!!!!!!!!!!!!!!!!!!!!!!!
    accountNumPoints += 1;

    // Increase unlock time
    ethers.provider.send("evm_mine");
    blockNumberBefore1 = await ethers.provider.getBlockNumber("latest");
    //console.log("block number before veCRV", blockNumberBefore);

    tx1 = await veCRV.increase_unlock_time("1600393082");
    tx2 = await ve.increaseUnlockTime(6 * oneWeek);

    blockNumberAfter1 = await ethers.provider.getBlockNumber("latest");
    //console.log("block number after ve", blockNumberAfter);
    ethers.provider.send("evm_mine");
    await tx1.wait();
    await tx2.wait();
    ethers.provider.send("evm_mine");
    blockNumberBefore2 = await ethers.provider.getBlockNumber("latest");
    //console.log("block number before veCRV", blockNumberBefore);

    tx1 = await veCRV.connect(user).increase_unlock_time("1602207482");
    tx2 = await ve.connect(user).increaseUnlockTime(9 * oneWeek);

    blockNumberAfter2 = await ethers.provider.getBlockNumber("latest");
    //console.log("block number after ve", blockNumberAfter);
    ethers.provider.send("evm_mine");
    await tx1.wait();
    await tx2.wait();

    // Get the storage values
    if (blockNumberAfter1 == blockNumberBefore1 && blockNumberAfter2 == blockNumberBefore2) {
        console.log("Checking increase unlock time");
        for (let i = 0; i < accounts.length; i++) {
            let veCRVLockedBalance = await veCRV.locked(accounts[i]);
            let veCRVUserPoint = await veCRV.user_point_history(accounts[i], accountNumPoints + 1);

            let veLockedBalance = await ve.mapLockedBalances(accounts[i]);
            let veUserPoint = await ve.mapUserPoints(accounts[i], accountNumPoints);

            // Compare results
            expect(veCRVLockedBalance.amount).to.equal(veLockedBalance.amount);
            expect(veCRVLockedBalance.end).to.equal(veLockedBalance.endTime);
            expect(veCRVUserPoint.bias).to.equal(veUserPoint.bias);
            expect(veCRVUserPoint.slope).to.equal(veUserPoint.slope);
            expect(veCRVUserPoint.ts).to.equal(veUserPoint.ts);
            expect(veCRVUserPoint.blk).to.equal(veUserPoint.blockNumber);

            totalNumPoints += 1;
            let veCRVSupplyPoint = await veCRV.point_history(totalNumPoints);
            let veSupplyPoint = await ve.mapSupplyPoints(totalNumPoints);
            expect(veCRVSupplyPoint.bias).to.equal(veSupplyPoint.bias);
            expect(veCRVSupplyPoint.slope).to.equal(veSupplyPoint.slope);
            expect(veCRVSupplyPoint.ts).to.equal(veSupplyPoint.ts);
            expect(veCRVSupplyPoint.blk).to.equal(veSupplyPoint.blockNumber);
        }
    }


    // !!!!!!!!!!!!!!!!!!!!! WITHDRAW !!!!!!!!!!!!!!!!!!!!!!!!!!
    accountNumPoints += 1;

    // Move pass the deployer time of unlock
    ethers.provider.send("evm_increaseTime", [7 * oneWeek]);
    ethers.provider.send("evm_mine");
    ethers.provider.send("evm_mine");
    blockNumberBefore1 = await ethers.provider.getBlockNumber("latest");
    //    console.log("block number before veCRV", blockNumberBefore);

    tx1 = await veCRV.withdraw();
    tx2 = await ve.withdraw();

    blockNumberAfter1 = await ethers.provider.getBlockNumber("latest");
    //    console.log("block number before veCRV", blockNumberAfter1);
    ethers.provider.send("evm_mine");
    await tx1.wait();
    await tx2.wait();

    if (blockNumberAfter1 == blockNumberBefore1) {
        // Get the storage values
        let veCRVLockedBalance = await veCRV.locked(deployer.address);
        let numLastPoint = await veCRV.user_point_epoch(deployer.address);
        let veCRVUserPoint = await veCRV.user_point_history(deployer.address, numLastPoint);
        let numLastSupplyPoint = await veCRV.epoch();
        let veCRVSupplyPoint = await veCRV.point_history(numLastSupplyPoint);

        let veLockedBalance = await ve.mapLockedBalances(deployer.address);
        let veUserPoint = await ve.mapUserPoints(deployer.address, numLastPoint - 1);
        let veSupplyPoint = await ve.mapSupplyPoints(numLastSupplyPoint);

        // Compare results
        console.log("Checking withdraw of deployer");
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

    // !!!!!!!!!!!!!!!!!!!!! CREATE LOCK ONLY FOR DEPLOYER !!!!!!!!!!!!!!!!!!!!!!!!!!
    totalNumPoints += 1;
    accountNumPoints += 1;

    // Move pass the deployer time of unlock
    ethers.provider.send("evm_mine");
    blockNumberBefore1 = await ethers.provider.getBlockNumber("latest");
    //    console.log("block number before veCRV", blockNumberBefore);

    tx1 = await veCRV.create_lock(fiveOLASBalance, "1604021882");
    tx2 = await ve.createLock(fiveOLASBalance, 5 * oneWeek);

    blockNumberAfter1 = await ethers.provider.getBlockNumber("latest");
    //    console.log("block number before veCRV", blockNumberAfter1);
    ethers.provider.send("evm_mine");
    await tx1.wait();
    await tx2.wait();

    // Get the storage values
    if (blockNumberAfter1 == blockNumberBefore1) {
        let veCRVLockedBalance = await veCRV.locked(deployer.address);
        let numLastPoint = await veCRV.user_point_epoch(deployer.address);
        let veCRVUserPoint = await veCRV.user_point_history(deployer.address, numLastPoint);
        let numLastSupplyPoint = await veCRV.epoch();
        let veCRVSupplyPoint = await veCRV.point_history(numLastSupplyPoint);

        let veLockedBalance = await ve.mapLockedBalances(deployer.address);
        let veUserPoint = await ve.mapUserPoints(deployer.address, numLastPoint - 1);
        let veSupplyPoint = await ve.mapSupplyPoints(numLastSupplyPoint);

        // Compare results
        console.log("Checking create lock of deployer only");
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


    // !!!!!!!!!!!!!!!!!!!!! WITHDRAW ALL !!!!!!!!!!!!!!!!!!!!!!!!!!
    // Move pass the deployer time of unlock
    ethers.provider.send("evm_increaseTime", [7 * oneWeek]);
    ethers.provider.send("evm_mine");
    ethers.provider.send("evm_mine");
    blockNumberBefore1 = await ethers.provider.getBlockNumber("latest");
    //    console.log("block number before veCRV", blockNumberBefore);

    tx1 = await veCRV.withdraw();
    tx2 = await ve.withdraw();

    blockNumberAfter1 = await ethers.provider.getBlockNumber("latest");
    //    console.log("block number before veCRV", blockNumberAfter1);
    ethers.provider.send("evm_mine");
    await tx1.wait();
    await tx2.wait();
    ethers.provider.send("evm_mine");
    blockNumberBefore2 = await ethers.provider.getBlockNumber("latest");
    //    console.log("block number before veCRV", blockNumberBefore);

    tx1 = await veCRV.connect(user).withdraw();
    tx2 = await ve.connect(user).withdraw();

    blockNumberAfter2 = await ethers.provider.getBlockNumber("latest");
    //    console.log("block number before veCRV", blockNumberAfter1);
    ethers.provider.send("evm_mine");
    await tx1.wait();
    await tx2.wait();

    // Get the storage values
    if (blockNumberAfter1 == blockNumberBefore1 && blockNumberAfter2 == blockNumberBefore2) {
        for (let i = 0; i < accounts.length; i++) {
            let veCRVLockedBalance = await veCRV.locked(accounts[i]);
            let numLastPoint = await veCRV.user_point_epoch(accounts[i]);
            let veCRVUserPoint = await veCRV.user_point_history(accounts[i], numLastPoint);

            let veLockedBalance = await ve.mapLockedBalances(accounts[i]);
            let veUserPoint = await ve.mapUserPoints(accounts[i], numLastPoint - 1);

            // Compare results
            expect(veCRVLockedBalance.amount).to.equal(veLockedBalance.amount);
            expect(veCRVLockedBalance.end).to.equal(veLockedBalance.endTime);
            expect(veCRVUserPoint.bias).to.equal(veUserPoint.bias);
            expect(veCRVUserPoint.slope).to.equal(veUserPoint.slope);
            expect(veCRVUserPoint.ts).to.equal(veUserPoint.ts);
            expect(veCRVUserPoint.blk).to.equal(veUserPoint.blockNumber);

            let numLastSupplyPoint = await veCRV.epoch();
            let veCRVSupplyPoint = await veCRV.point_history(numLastSupplyPoint);
            let veSupplyPoint = await ve.mapSupplyPoints(numLastSupplyPoint);
            expect(veCRVSupplyPoint.bias).to.equal(veSupplyPoint.bias);
            expect(veCRVSupplyPoint.slope).to.equal(veSupplyPoint.slope);
            expect(veCRVSupplyPoint.ts).to.equal(veSupplyPoint.ts);
            expect(veCRVSupplyPoint.blk).to.equal(veSupplyPoint.blockNumber);
        }
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
