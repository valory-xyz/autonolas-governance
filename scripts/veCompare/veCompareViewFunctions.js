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
    let accountInitBlockNumbers = new Array(accounts.length);
    let accountFinalBlockNumbers = new Array(accounts.length);
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
    let block = await ethers.provider.getBlock(blockNumber);
    console.log("block timestamp after original VE deployment", block.timestamp);

    // block number for the first transaction - 10655231, createLock(66500000000000000000, 1598578682), block.timestamp == 1597369454
    // unlockTime == 1598486400

    const VE = await ethers.getContractFactory("veOLAS");
    const ve = await VE.deploy(olas.address, "name", "symbol");
    await ve.deployed();
    const deployBlockNumber = await ethers.provider.getBlockNumber("latest");

    // Change the token storage slot value from CRV to OLAS address
    const tokenSlot = "0x0";
    // Storage value must be a 32 bytes long padded with leading zeros hex string
    const value = ethers.utils.hexlify(ethers.utils.zeroPad(olas.address, 32));
    await ethers.provider.send("hardhat_setStorageAt", [veCRV.address, tokenSlot, value]);
    //console.log("veCRV token now", await veCRV.token());
    //console.log("OLAS address", olas.address);

    // Deploy veOLAS wrapper contract
    const WVE = await ethers.getContractFactory("wveOLAS");
    const wveProxy = await WVE.deploy(ve.address);
    await wveProxy.deployed();

    const wve = await ethers.getContractAt("veOLAS", wveProxy.address);

    // Approve both ve tokens to a max amount
    await olas.approve(veCRV.address, ethers.constants.MaxUint256);
    await olas.connect(user).approve(veCRV.address, ethers.constants.MaxUint256);
    await olas.approve(ve.address, ethers.constants.MaxUint256);
    await olas.connect(user).approve(ve.address, ethers.constants.MaxUint256);


    // !!!!!!!!!!!!!!!!!!!!! CREATE INITIAL LOCK !!!!!!!!!!!!!!!!!!!!!!!!!!
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
    // We cannot proceed if block number for both veCRV and veOLAS don't match
    expect(blockNumberAfter1).to.equal(blockNumberBefore1);

    // Record the first block number where the first account has created its first point
    accountInitBlockNumbers[0] = await ethers.provider.getBlockNumber("latest");

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
    expect(blockNumberAfter2).to.equal(blockNumberBefore2);

    accountInitBlockNumbers[1] = await ethers.provider.getBlockNumber("latest");


    // !!!!!!!!!!!!!!!!!!!!! INCREASE AMOUNT !!!!!!!!!!!!!!!!!!!!!!!!!!
    const numSteps = 4;

    for (let i = 0; i < numSteps; i++) {
        // Increase time twice and mine two blocks
        ethers.provider.send("evm_increaseTime", [15]);
        ethers.provider.send("evm_mine");
        ethers.provider.send("evm_increaseTime", [15]);
        ethers.provider.send("evm_mine");
        ethers.provider.send("evm_mine");

        // Increase amount
        blockNumberBefore1 = await ethers.provider.getBlockNumber("latest");
        //console.log("block number before veCRV", blockNumberBefore);

        tx1 = await veCRV.increase_amount(threeOLASBalance);
        tx2 = await ve.increaseAmount(threeOLASBalance);

        blockNumberAfter1 = await ethers.provider.getBlockNumber("latest");
        //console.log("block number after ve", blockNumberAfter);
        ethers.provider.send("evm_mine");
        await tx1.wait();
        await tx2.wait();
        expect(blockNumberAfter1).to.equal(blockNumberBefore1);

        accountFinalBlockNumbers[0] = await ethers.provider.getBlockNumber("latest");

        // Increase time and mine two blocks
        ethers.provider.send("evm_increaseTime", [15]);
        ethers.provider.send("evm_mine");
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
        expect(blockNumberAfter2).to.equal(blockNumberBefore2);

        accountFinalBlockNumbers[1] = await ethers.provider.getBlockNumber("latest");
    }

    // Record the difference between the initial and the final block numbers
    const accountNumBlocks = [accountFinalBlockNumbers[0] - accountInitBlockNumbers[0],
        accountFinalBlockNumbers[1] - accountInitBlockNumbers[1]];
    const supplyNumBlocks = accountFinalBlockNumbers[1] - deployBlockNumber;

    console.log("numBlocks deployer", accountNumBlocks[0]);
    console.log("numBlocks user", accountNumBlocks[1]);
    console.log("supplyNumBlocks", supplyNumBlocks);

    // Loop over user points
    for (let i = 0; i < accounts.length; i++) {
        const veCRVLastUserSlope = await veCRV.get_last_user_slope(accounts[i]);
        const veLastUserPoint = await wve.getLastUserPoint(accounts[i]);
        expect(veCRVLastUserSlope).to.equal(veLastUserPoint.slope);

        //for (let iBlock = accountInitBlockNumbers[i]; iBlock <= accountFinalBlockNumbers[i]; iBlock++)
        for (let iBlock = deployBlockNumber; iBlock <= accountFinalBlockNumbers[i]; iBlock++) {
            const veCRVBalanceOf = await veCRV["balanceOf(address)"](accounts[i]);
            const veVotes = await wve.getVotes(accounts[i]);
            expect(veCRVBalanceOf).to.equal(veVotes);

            const veCRVBalanceOfAt = await veCRV.balanceOfAt(accounts[i], iBlock);
            const vePastVotes = await wve.getPastVotes(accounts[i], iBlock);
            expect(veCRVBalanceOfAt).to.equal(vePastVotes);
        }
    }

    const veCRVTotalSupply = await veCRV["totalSupply()"]();
    const veTotalSupplyLocked = await wve.totalSupplyLocked();
    expect(veCRVTotalSupply).to.equal(veTotalSupplyLocked);
    // Loop over supply points
    for (let iBlock = deployBlockNumber; iBlock <= accountFinalBlockNumbers[1]; iBlock++) {
        const veCRVTotalSupplyAt = await veCRV.totalSupplyAt(iBlock);
        const vePastTotalSupply = await wve.getPastTotalSupply(iBlock);
        expect(veCRVTotalSupplyAt).to.equal(vePastTotalSupply);
    }

    // totalSupplyAtT must be called from the very last written point into the future
    block = await ethers.provider.getBlock(accountFinalBlockNumbers[1]);
    const lastBlockTime = block.timestamp;
    for (let iTime = lastBlockTime; iTime <= lastBlockTime + 3 * oneWeek; iTime += oneWeek) {
        const veCRVTotalSupplyAtT = await veCRV["totalSupply(uint256)"](iTime);
        const veTotalSupplyLockedAtT = await wve.totalSupplyLockedAtT(iTime);
        expect(veCRVTotalSupplyAtT).to.equal(veTotalSupplyLockedAtT);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
