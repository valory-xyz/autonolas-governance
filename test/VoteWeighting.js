/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Voting Escrow OLAS", function () {
    let olas;
    let ve;
    let vw;
    let signers;
    const initialMint = "1000000000000000000000000"; // 1000000
    const oneWeek = 7 * 86400;
    const oneOLASBalance = ethers.utils.parseEther("1");
    const twoOLASBalance = ethers.utils.parseEther("2");
    const tenOLASBalance = ethers.utils.parseEther("10");
    const AddressZero = "0x" + "0".repeat(40);
    const overflowNum96 = "8" + "0".repeat(28);

    beforeEach(async function () {
        const OLAS = await ethers.getContractFactory("OLAS");
        olas = await OLAS.deploy();
        await olas.deployed();

        signers = await ethers.getSigners();
        await olas.mint(signers[0].address, initialMint);

        const VE = await ethers.getContractFactory("veOLAS");
        ve = await VE.deploy(olas.address, "Voting Escrow OLAS", "veOLAS");
        await ve.deployed();

        const VoteWeighting = await ethers.getContractFactory("VoteWeighting");
        vw = await VoteWeighting.deploy(ve.address);
        await vw.deployed();
    });

    context("Initialization", async function () {
        it("veOLAS", async function () {
            // Checks for the veOLAS account
            const veAddress = await vw.ve();
            expect(ve.address).to.equal(veAddress);
        });
    });
});
