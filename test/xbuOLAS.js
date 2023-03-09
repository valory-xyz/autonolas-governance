/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Time shifting buOLAS", function () {
    let olas;
    let bu;
    let signers;
    const initialMint = "1000000000000000000000000"; // 1000000
    const oneOLABalance = ethers.utils.parseEther("1");
    const numSteps = 4;

    beforeEach(async function () {
        const OLAS = await ethers.getContractFactory("OLAS");
        olas = await OLAS.deploy();
        await olas.deployed();

        signers = await ethers.getSigners();
        await olas.mint(signers[0].address, initialMint);

        const BU = await ethers.getContractFactory("buOLAS");
        bu = await BU.deploy(olas.address, "name", "symbol");
        await bu.deployed();
    });

    context("Time sensitive functions. This must be the very last test", async function () {
        it("Should fail when creating a lock after the year of 2106", async function () {
            const account = signers[1].address;
            await olas.approve(bu.address, oneOLABalance);

            // Move time to the year 2106
            const year2106 = 4291821394;
            ethers.provider.send("evm_increaseTime", [year2106]);
            ethers.provider.send("evm_mine");
            await expect(
                bu.createLockFor(account, oneOLABalance, numSteps)
            ).to.be.revertedWithCustomError(bu, "Overflow");
        });
    });
});
