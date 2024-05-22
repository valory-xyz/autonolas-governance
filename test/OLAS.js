/*global describe, context, beforeEach, it*/
const { ethers } = require("hardhat");
const { expect } = require("chai");
const { signERC2612Permit } = require("eth-permit");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("OLAS", function () {
    let deployer;
    let treasury;
    let bob;
    let alice;
    let olas;
    let olasFactory;
    const initSupply = "5" + "0".repeat(26);
    const oneYear = 365 * 86400;
    const threeYears = 3 * oneYear;
    const nineYears = 9 * oneYear;
    const tenYears = 10 * oneYear;
    const amount = 100;
    const AddressZero = "0x" + "0".repeat(40);
    const maxNum256 = "115792089237316195423570985008687907853269984665640564039457584007913129639935";

    beforeEach(async function () {
        [deployer, treasury, bob, alice] = await ethers.getSigners();
        olasFactory = await ethers.getContractFactory("OLAS");
        // Treasury address is deployer by default
        olas = await olasFactory.deploy();
        await olas.mint(deployer.address, initSupply);
        // Changing the treasury address
        await olas.connect(deployer).changeMinter(treasury.address);
    });

    context("Initialization", async function () {
        it("correctly constructs an ERC20", async () => {
            expect(await olas.name()).to.equal("Autonolas");
            expect(await olas.symbol()).to.equal("OLAS");
            expect(await olas.decimals()).to.equal(18);
        });

        it("Change owner", async function () {
            const owner = deployer;
            const account = bob;

            // Trying to change owner from a non-owner account address
            await expect(
                olas.connect(account).changeOwner(account.address)
            ).to.be.revertedWithCustomError(olas, "ManagerOnly");

            // Trying to change owner for the zero address
            await expect(
                olas.connect(owner).changeOwner(AddressZero)
            ).to.be.revertedWithCustomError(olas, "ZeroAddress");

            // Changing the owner
            await olas.connect(owner).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                olas.connect(owner).changeOwner(owner.address)
            ).to.be.revertedWithCustomError(olas, "ManagerOnly");
        });

        it("Change minter", async function () {
            const owner = deployer;
            const account = bob;

            // Trying to change minter from a non-owner account address
            await expect(
                olas.connect(account).changeMinter(account.address)
            ).to.be.revertedWithCustomError(olas, "ManagerOnly");

            // Trying to change minter for the zero address
            await expect(
                olas.connect(owner).changeMinter(AddressZero)
            ).to.be.revertedWithCustomError(olas, "ZeroAddress");

            // Changing the minter
            await olas.connect(owner).changeMinter(account.address);
        });
    });

    context("Mint", () => {
        it("Mint must be done by manager", async function () {
            await expect(
                olas.connect(bob).mint(bob.address, amount)
            ).to.be.revertedWithCustomError(olas, "ManagerOnly");
        });

        it("Increases total supply", async function () {
            const supplyBefore = await olas.totalSupply();
            await olas.connect(treasury).mint(bob.address, amount);
            expect(supplyBefore.add(amount)).to.equal(await olas.totalSupply());
        });
    });

    context("Burn", async function () {
        beforeEach(async function () {
            await olas.connect(treasury).mint(bob.address, amount);
        });

        it("Reduces the total supply", async function () {
            const supplyBefore = await olas.totalSupply();
            await olas.connect(bob).burn(10);
            expect(supplyBefore.sub(10)).to.equal(await olas.totalSupply());
        });
    });

    context("Transfer", async function () {
        it("Transfer from self", async function () {
            await olas.connect(treasury).mint(bob.address, amount);
            await olas.connect(bob).transfer(alice.address, amount);
            expect(await olas.balanceOf(alice.address)).to.equal(amount);
        });

        it("Transfer from via approve", async function () {
            await olas.connect(treasury).mint(bob.address, amount);
            await olas.connect(bob).approve(alice.address, amount);
            await olas.connect(alice).transferFrom(bob.address, alice.address, amount);
            expect(await olas.balanceOf(alice.address)).to.equal(amount);
        });

        it("Transfer from via permit", async function () {
            await olas.connect(treasury).mint(bob.address, amount);
            const result = await signERC2612Permit(bob, olas.address, bob.address, alice.address, amount);
            await olas.permit(bob.address, alice.address, amount, result.deadline,
                result.v, result.r, result.s);
            await olas.connect(alice).transferFrom(bob.address, alice.address, amount);
            expect(await olas.balanceOf(alice.address)).to.equal(amount);
        });

        it("Transfer from with increase allowance", async function () {
            await olas.connect(treasury).mint(bob.address, amount);
            await olas.connect(bob).approve(alice.address, amount - 50);
            // Trying to do transferFrom with insufficient allowance
            await expect(
                olas.connect(alice).transferFrom(bob.address, alice.address, amount)
            ).to.be.reverted;
            // Increasing allowance
            await olas.connect(bob).increaseAllowance(alice.address, amount - 50);
            await olas.connect(alice).transferFrom(bob.address, alice.address, amount);
            expect(await olas.balanceOf(alice.address)).to.equal(amount);
        });

        it("Transfer from with maximum allowance", async function () {
            await olas.connect(treasury).mint(bob.address, amount);
            await olas.connect(bob).approve(alice.address, maxNum256);
            // Decreasing allowance will not change it and thus transferFrom will go through
            await olas.connect(bob).decreaseAllowance(alice.address, maxNum256);
            await olas.connect(alice).transferFrom(bob.address, alice.address, amount);
            expect(await olas.balanceOf(alice.address)).to.equal(amount);
        });

        it("Transfer from with decrease allowance", async function () {
            await olas.connect(treasury).mint(bob.address, amount);
            await olas.connect(bob).approve(alice.address, amount);
            // Decreasing allowance
            await olas.connect(bob).decreaseAllowance(alice.address, amount - 50);
            // Trying to do transferFrom for a full amount with insufficient allowance
            await expect(
                olas.connect(alice).transferFrom(bob.address, alice.address, amount)
            ).to.be.reverted;
            await olas.connect(alice).transferFrom(bob.address, alice.address, amount - 50);
            expect(await olas.balanceOf(alice.address)).to.equal(amount - 50);
        });
    });

    context("Mint schedule", async function () {
        it("Should fail when mint more than a supplyCap within the first ten years", async () => {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const supplyCap = await olas.tenYearSupplyCap();
            let amount = supplyCap;
            // Mint more than the supply cap is not possible
            let totalSupply = await olas.totalSupply();
            await olas.connect(treasury).mint(deployer.address, amount);
            expect(await olas.totalSupply()).to.equal(totalSupply);

            // Move 9 years in time
            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            await helpers.time.increase(block.timestamp + nineYears + 1000);

            // Mint up to the supply cap
            amount = "5" + "0".repeat(26);
            await olas.connect(treasury).mint(deployer.address, amount);

            // Check the total supply that must be equal to the supply cap
            totalSupply = await olas.totalSupply();
            expect(totalSupply).to.equal(supplyCap);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Mint and burn after ten years", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const supplyCap = await olas.tenYearSupplyCap();
            let amount = supplyCap;
            // Mint more than the supply cap is not possible
            let totalSupply = await olas.totalSupply();
            await olas.connect(treasury).mint(deployer.address, amount);
            expect(await olas.totalSupply()).to.equal(totalSupply);

            // Move 10 years in time and mine a new block with that timestamp
            let block = await ethers.provider.getBlock("latest");
            await helpers.time.increaseTo(block.timestamp + tenYears + 10);

            // Calculate expected supply cap starting from the max for 10 years, i.e. 1 billion
            const supplyCapFraction = await olas.maxMintCapFraction();
            let expectedSupplyCap = supplyCap.add((supplyCap.mul(supplyCapFraction)).div(100));

            // Mint up to the supply cap that is up to the renewed supply cap after ten years
            // New total supply is 1 * 1.02 = 1.02 billion. We can safely mint 9 million
            amount = "519" + "0".repeat(24);
            await olas.connect(treasury).mint(deployer.address, amount);
            totalSupply = await olas.totalSupply();
            expect(Number(totalSupply)).to.lessThan(Number(expectedSupplyCap));
            //console.log("updated total supply", totalSupply);

            // Mint more than a new total supply must not go through (will not change the supply)
            amount = "2" + "0".repeat(24);
            await olas.connect(treasury).mint(deployer.address, amount);
            expect(await olas.totalSupply()).to.equal(totalSupply);

            // Move 3 more years in time, in addition to what we have already surpassed 10 years
            // So it will be the beginning of a year 4 after first 10 years
            block = await ethers.provider.getBlock("latest");
            await helpers.time.increaseTo(block.timestamp + threeYears + 1000);
            // Calculate max supply cap after 4 years in total
            expectedSupplyCap = supplyCap;
            for (let i = 0; i < 4; ++i) {
                expectedSupplyCap += (expectedSupplyCap * supplyCapFraction) / 100;
            }

            // The max supply now is 1,082,432,160 * E18
            // Mint 60 million more
            amount = "6" + "0".repeat(25);
            await olas.connect(treasury).mint(deployer.address, amount);

            // Mint 5 more million must not change the total supply due to the overflow
            totalSupply = await olas.totalSupply();
            amount = "5" + "0".repeat(24);
            await olas.connect(treasury).mint(deployer.address, amount);
            expect(await olas.totalSupply()).to.equal(totalSupply);

            // Burn the amount such that the total supply drops below 1 billion
            amount = "1" + "0".repeat(26);
            // Total supply minus the amount to be burned
            const expectedTotalSupply = new ethers.BigNumber.from(await olas.totalSupply()).sub(amount);
            await olas.connect(deployer).burn(amount);
            // Check the final total amount
            expect(await olas.totalSupply()).to.equal(expectedTotalSupply);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });
    });
});
