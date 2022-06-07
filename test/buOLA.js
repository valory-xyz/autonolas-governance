/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("buOLA", function () {
    let ola;
    let bu;
    let signers;
    const initialMint = "1000000000000000000000000"; // 1000000
    const oneYear = 365 * 86400;
    const quarterOLABalance = ethers.utils.parseEther("0.25");
    const oneOLABalance = ethers.utils.parseEther("1");
    const twoOLABalance = ethers.utils.parseEther("2");
    const tenOLABalance = ethers.utils.parseEther("10");
    const AddressZero = "0x" + "0".repeat(40);

    beforeEach(async function () {
        const OLA = await ethers.getContractFactory("OLA");
        ola = await OLA.deploy(0);
        await ola.deployed();

        signers = await ethers.getSigners();
        await ola.mint(signers[0].address, initialMint);

        const BU = await ethers.getContractFactory("buOLA");
        bu = await BU.deploy(ola.address, "name", "symbol");
        await bu.deployed();
    });

    context("Locks", async function () {
        it("Should fail when creating a lock with zero value or wrong number of steps", async function () {
            const account = signers[1].address;
            await ola.approve(bu.address, oneOLABalance);

            await expect(
                bu.createLockFor(AddressZero, 0, 0)
            ).to.be.revertedWith("ZeroAddress");

            await expect(
                bu.createLockFor(account, 0, 0)
            ).to.be.revertedWith("ZeroValue");

            await expect(
                bu.createLockFor(account, oneOLABalance, 0)
            ).to.be.revertedWith("ZeroValue");

            await expect(
                bu.createLockFor(account, oneOLABalance, 11)
            ).to.be.revertedWith("Overflow");
        });

        it("Create lock for", async function () {
            const owner = signers[0];
            const account = signers[1];

            // Approve owner for 1 OLA by buOLA
            await ola.connect(owner).approve(bu.address, oneOLABalance);

            // Define 4 years for the lock duration
            const numSteps = 4;

            // Balance should be zero before the lock
            expect(await bu.balanceOf(account.address)).to.equal(0);
            // Create lock for the account address, which is called by the owner (approved for buOLA)
            await bu.connect(owner).createLockFor(account.address, oneOLABalance, numSteps);

            // Lock end is rounded by 1 week, as implemented by design
            const lockEnd = await bu.lockedEnd(account.address);
            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            expect(Math.floor(block.timestamp + oneYear * numSteps)).to.equal(lockEnd);

            // Try to create an additional lock to the account address that already has a lock
            await expect(
                bu.connect(owner).createLockFor(account.address, oneOLABalance, numSteps)
            ).to.be.revertedWith("LockedValueNotZero");

            // Check the total supply to be equal to the account locked balance
            let supply = await bu.totalSupply();
            expect(supply).to.equal(oneOLABalance);

            // Release amount must be zero at the very beginning
            let amount = await bu.releasableAmount(account.address);
            expect(amount).to.equal(0);
            // Balance of account must be equal to the locked account
            expect(await bu.balanceOf(account.address)).to.equal(oneOLABalance);

            // Move one year in time
            ethers.provider.send("evm_increaseTime", [oneYear + 100]);
            ethers.provider.send("evm_mine");
            // Now the releasable amount must be equal to 1/4 of the total amount
            amount = await bu.releasableAmount(account.address);
            expect(amount).to.equal(quarterOLABalance);

            // Move five years in time
            ethers.provider.send("evm_increaseTime", [5 * oneYear + 100]);
            ethers.provider.send("evm_mine");
            // The releasable amount must be the full amount
            amount = await bu.releasableAmount(account.address);
            expect(amount).to.equal(oneOLABalance);

            // Check the balance that is still the same as the locked one
            supply = await bu.totalSupply();
            expect(supply).to.equal(oneOLABalance);
        });
    });

    context("Withdraw", async function () {
        it("Withdraw", async function () {
            const owner = signers[0];
            const account = signers[1];

            // Approve owner for 1 OLA by buOLA that will be locked for account
            await ola.connect(owner).approve(bu.address, oneOLABalance);

            // Define 4 years for the lock duration
            const numSteps = 4;
            await bu.connect(owner).createLockFor(account.address, oneOLABalance, numSteps);

            // Try to withdraw early
            await expect(bu.connect(account).withdraw()).to.be.revertedWith("LockNotExpired");
            // Move one year in time
            ethers.provider.send("evm_increaseTime", [oneYear + 100]);
            ethers.provider.send("evm_mine");
            // Withdraw must be equal to 1/4 of the total amount
            expect(await ola.balanceOf(account.address)).to.equal(0);
            await bu.connect(account).withdraw();
            expect(await ola.balanceOf(account.address)).to.equal(quarterOLABalance);

            // Try to withdraw more now
            await expect(bu.connect(account).withdraw()).to.be.revertedWith("LockNotExpired");

            // Move time after the lock duration
            ethers.provider.send("evm_increaseTime", [3 * oneYear + 100]);
            ethers.provider.send("evm_mine");

            // Now withdraw must get us the rest
            await bu.connect(account).withdraw();
            expect(await ola.balanceOf(account.address)).to.equal(oneOLABalance);
        });

        it("Withdraw with revoke", async function () {
            const owner = signers[0];
            const account = signers[1];

            // Approve owner for 1 OLA by buOLA that will be locked for account
            await ola.connect(owner).approve(bu.address, oneOLABalance);

            // Define 4 years for the lock duration
            const numSteps = 4;
            await bu.connect(owner).createLockFor(account.address, oneOLABalance, numSteps);
            // Check the balanceOf that must be equal to the full locked amount
            let balance = await bu.balanceOf(account.address);
            expect(balance).to.equal(oneOLABalance);

            // Move one year in time
            ethers.provider.send("evm_increaseTime", [oneYear + 100]);
            ethers.provider.send("evm_mine");
            // Revoke at this point of time
            await bu.connect(owner).revoke([account.address]);
            // The buOLA balanceOf must be equal to the releasable amount after the revoke
            balance = await bu.balanceOf(account.address);
            expect(balance).to.equal(quarterOLABalance);

            // Move time after the full lock duration
            ethers.provider.send("evm_increaseTime", [3 * oneYear + 100]);
            ethers.provider.send("evm_mine");

            // The releasable amount must still be the 1/4 amount, since the rest was revoked
            let amount = await bu.releasableAmount(account.address);
            expect(amount).to.equal(quarterOLABalance);

            // Withdraw must be equal to 1/4 of the total amount since another 3/4 has been revoked
            expect(await ola.balanceOf(account.address)).to.equal(0);
            // Before the withdraw the total supply is still equal to the full balance
            let supply = await bu.totalSupply();
            expect(supply).to.equal(oneOLABalance);
            // Withdraw what we can for the account
            await bu.connect(account).withdraw();
            expect(await ola.balanceOf(account.address)).to.equal(quarterOLABalance);
            // Now the balance is zero, since the rest of 3/4 tokens were burned
            supply = await bu.totalSupply();
            expect(supply).to.equal(0);

            // Now there is no releasable amount left
            amount = await bu.releasableAmount(account.address);
            expect(amount).to.equal(0);
        });
    });

    context("IERC20 functions", async function () {
        it("Check all the related functions", async function () {
            const deployer = signers[0].address;
            const user = signers[1].address;
            // Try to call transfer-related functions for buOLA
            await expect(
                bu.approve(user, oneOLABalance)
            ).to.be.revertedWith("NonTransferable");
            await expect(
                bu.allowance(deployer, user)
            ).to.be.revertedWith("NonTransferable");
            await expect(
                bu.transfer(user, oneOLABalance)
            ).to.be.revertedWith("NonTransferable");
            await expect(
                bu.transferFrom(deployer, user, oneOLABalance)
            ).to.be.revertedWith("NonTransferable");
        });
    });
});
