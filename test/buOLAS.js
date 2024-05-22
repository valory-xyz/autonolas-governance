/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("buOLAS", function () {
    let olas;
    let bu;
    let signers;
    const initialMint = "1000000000000000000000000"; // 1000000
    const oneYear = 365 * 86400;
    const quarterOLASBalance = ethers.utils.parseEther("0.25");
    const oneOLASBalance = ethers.utils.parseEther("1");
    const twoOLASBalance = ethers.utils.parseEther("2");
    const AddressZero = "0x" + "0".repeat(40);
    const overflowNum96 = "8" + "0".repeat(28);
    const uint256Limit = "115792089237316195423570985008687907853269984665640564039456584007913129639936";

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

    context("Initialization", async function () {
        it("Changing owner", async function () {
            const owner = signers[0];
            const account = signers[1];

            // Trying to change owner from a non-owner account address
            await expect(
                bu.connect(account).changeOwner(account.address)
            ).to.be.revertedWithCustomError(bu, "OwnerOnly");

            // Trying to change owner for the zero address
            await expect(
                bu.connect(owner).changeOwner(AddressZero)
            ).to.be.revertedWithCustomError(bu, "ZeroAddress");

            // Changing the owner
            await bu.connect(owner).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                bu.connect(owner).changeOwner(owner.address)
            ).to.be.revertedWithCustomError(bu, "OwnerOnly");
        });

        it("Interface support", async function () {
            // Checks for the compatibility with IERC165
            const interfaceIdIERC165 = "0x01ffc9a7";
            const checkInterfaceId = await bu.supportsInterface(interfaceIdIERC165);
            expect(checkInterfaceId).to.equal(true);
        });
    });

    context("Locks", async function () {
        it("Should fail when creating a lock with zero value or wrong number of steps", async function () {
            const account = signers[1].address;
            await olas.approve(bu.address, oneOLASBalance);

            await expect(
                bu.createLockFor(AddressZero, 0, 0)
            ).to.be.revertedWithCustomError(bu, "ZeroAddress");

            await expect(
                bu.createLockFor(account, 0, 0)
            ).to.be.revertedWithCustomError(bu, "ZeroValue");

            await expect(
                bu.createLockFor(account, oneOLASBalance, 0)
            ).to.be.revertedWithCustomError(bu, "ZeroValue");

            await expect(
                bu.createLockFor(account, overflowNum96, 1)
            ).to.be.revertedWithCustomError(bu, "Overflow");

            await expect(
                bu.createLockFor(account, oneOLASBalance, 11)
            ).to.be.revertedWithCustomError(bu, "Overflow");
        });

        it("Create lock for", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const owner = signers[0];
            const account = signers[1];

            // Approve owner for 1 OLAS by buOLAS
            await olas.connect(owner).approve(bu.address, oneOLASBalance);

            // Define 4 years for the lock duration
            const numSteps = 4;

            // Balance should be zero before the lock
            expect(await bu.balanceOf(account.address)).to.equal(0);
            // Create lock for the account address, which is called by the owner (approved for buOLAS)
            await bu.connect(owner).createLockFor(account.address, oneOLASBalance, numSteps);

            // Lock end is rounded by 1 week, as implemented by design
            const lockEnd = await bu.lockedEnd(account.address);
            const block = await ethers.provider.getBlock("latest");
            expect(Math.floor(block.timestamp + oneYear * numSteps)).to.equal(lockEnd);

            // Try to create an additional lock to the account address that already has a lock
            await expect(
                bu.connect(owner).createLockFor(account.address, oneOLASBalance, numSteps)
            ).to.be.revertedWithCustomError(bu, "LockedValueNotZero");

            // Check the total supply to be equal to the account locked balance
            let supply = await bu.totalSupply();
            expect(supply).to.equal(oneOLASBalance);

            // Release amount must be zero at the very beginning
            let amount = await bu.releasableAmount(account.address);
            expect(amount).to.equal(0);
            // Balance of account must be equal to the locked account
            expect(await bu.balanceOf(account.address)).to.equal(oneOLASBalance);

            // Move one year in time
            await helpers.time.increase(oneYear + 100);

            // Now the releasable amount must be equal to 1/4 of the total amount
            amount = await bu.releasableAmount(account.address);
            expect(amount).to.equal(quarterOLASBalance);

            // Move five years in time
            await helpers.time.increase(5 * oneYear + 100);

            // The releasable amount must be the full amount
            amount = await bu.releasableAmount(account.address);
            expect(amount).to.equal(oneOLASBalance);

            // Check the balance that is still the same as the locked one
            supply = await bu.totalSupply();
            expect(supply).to.equal(oneOLASBalance);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });
    });

    context("Withdraw", async function () {
        it("Withdraw", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const owner = signers[0];
            const account = signers[1];

            // Try to withdraw without any locks
            await bu.connect(account).withdraw();
            expect(await olas.balanceOf(account.address)).to.equal(0);

            // Approve owner for 1 OLAS by buOLAS that will be locked for account
            await olas.connect(owner).approve(bu.address, oneOLASBalance);

            // Define 4 years for the lock duration
            const numSteps = 4;
            await bu.connect(owner).createLockFor(account.address, oneOLASBalance, numSteps);

            // Try to withdraw early
            await expect(bu.connect(account).withdraw()).to.be.revertedWithCustomError(bu, "LockNotExpired");
            // Move one year in time
            await helpers.time.increase(oneYear + 100);
            
            // Withdraw must be equal to 1/4 of the total amount
            expect(await olas.balanceOf(account.address)).to.equal(0);
            await bu.connect(account).withdraw();
            expect(await olas.balanceOf(account.address)).to.equal(quarterOLASBalance);

            // Try to withdraw more now
            await expect(
                bu.connect(account).withdraw()
            ).to.be.revertedWithCustomError(bu, "LockNotExpired");

            // Move time after the lock duration
            await helpers.time.increase(3 * oneYear + 100);
            

            // Now withdraw must get us the rest
            await bu.connect(account).withdraw();
            expect(await olas.balanceOf(account.address)).to.equal(oneOLASBalance);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Withdraw with not divisible remainder", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const owner = signers[0];
            const account = signers[1];

            // Approve owner for 1 OLAS by buOLAS that will be locked for account
            await olas.connect(owner).approve(bu.address, oneOLASBalance);

            // Define 3 years for the lock duration
            const numSteps = 3;
            await bu.connect(owner).createLockFor(account.address, oneOLASBalance, numSteps);

            // Move one year in time
            await helpers.time.increase(oneYear + 100);
            
            // Withdraw must be equal to rounded 1/3 of the total amount
            const thirdOLASBalance = new ethers.BigNumber.from(oneOLASBalance).div(numSteps);
            await bu.connect(account).withdraw();
            const recoveredFullBalance = thirdOLASBalance.mul(numSteps);
            expect(await olas.balanceOf(account.address)).to.equal(thirdOLASBalance);
            // This proves that we can potentially lose only 1e(-18) tokens if we call revoke on non divisible remainder
            expect(recoveredFullBalance.add(1)).to.equal(oneOLASBalance);

            // Move time after the lock duration
            await helpers.time.increase(2 * oneYear + 100);
            

            // At the end we withdraw the remainder that gets the rest with 1e(-18) tokens that were not partitioned
            await bu.connect(account).withdraw();
            expect(await olas.balanceOf(account.address)).to.equal(oneOLASBalance);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Withdraw with revoke", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const owner = signers[0];
            const account = signers[1];

            // Approve owner for 1 OLAS by buOLAS that will be locked for account
            await olas.connect(owner).approve(bu.address, oneOLASBalance);

            // Define 4 years for the lock duration
            const numSteps = 4;
            await bu.connect(owner).createLockFor(account.address, oneOLASBalance, numSteps);
            // Check the balanceOf that must be equal to the full locked amount
            let balance = await bu.balanceOf(account.address);
            expect(balance).to.equal(oneOLASBalance);

            // Try to revoke not by the owner
            await expect(
                bu.connect(account).revoke([account.address])
            ).to.be.revertedWithCustomError(bu, "OwnerOnly");

            // Move one year in time
            await helpers.time.increase(oneYear + 100);
            
            // Revoke at this point of time
            await bu.connect(owner).revoke([account.address]);
            // The buOLAS balanceOf must be equal to the releasable amount after the revoke
            balance = await bu.balanceOf(account.address);
            expect(balance).to.equal(quarterOLASBalance);

            // Move time after the full lock duration
            await helpers.time.increase(3 * oneYear + 100);
            

            // The releasable amount must still be the 1/4 amount, since the rest was revoked
            let amount = await bu.releasableAmount(account.address);
            expect(amount).to.equal(quarterOLASBalance);

            // Withdraw must be equal to 1/4 of the total amount since another 3/4 has been revoked
            expect(await olas.balanceOf(account.address)).to.equal(0);
            // Before the withdraw the total supply is still equal to the full balance
            let supply = await bu.totalSupply();
            expect(supply).to.equal(oneOLASBalance);
            // Withdraw what we can for the account
            await bu.connect(account).withdraw();
            expect(await olas.balanceOf(account.address)).to.equal(quarterOLASBalance);
            // Now the balance is zero, since the rest of 3/4 tokens were burned
            supply = await bu.totalSupply();
            expect(supply).to.equal(0);

            // Now there is no releasable amount left
            amount = await bu.releasableAmount(account.address);
            expect(amount).to.equal(0);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Withdraw with revoke after the first withdraw", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const owner = signers[0];
            const account = signers[1];

            // Approve owner for 1 OLAS by buOLAS that will be locked for account
            await olas.connect(owner).approve(bu.address, oneOLASBalance);

            // Define 3 years for the lock duration
            const numSteps = 3;
            await bu.connect(owner).createLockFor(account.address, oneOLASBalance, numSteps);

            // Move one year in time
            await helpers.time.increase(oneYear + 100);
            
            // Withdraw after the first year
            await bu.connect(account).withdraw();

            // Move one more year in time
            await helpers.time.increase(oneYear + 100);
            
            // Revoke at this point of time
            await bu.connect(owner).revoke([account.address]);
            // The buOLAS balanceOf must be equal to the releasable amount after the revoke, which is 1/3
            const thirdOLASBalance = new ethers.BigNumber.from(oneOLASBalance).div(numSteps);
            const balance = await bu.balanceOf(account.address);
            expect(balance).to.equal(thirdOLASBalance);

            // The releasable amount must be the 1/3 amount, since the rest 1/3 was revoked
            let amount = await bu.releasableAmount(account.address);
            expect(amount).to.equal(thirdOLASBalance);

            const twoThirdsOLASBalance = thirdOLASBalance.mul(2);
            // Before the withdraw the total supply is equal to 2/3 of the full balance, since 1/3 was already withdrawn
            let supply = await bu.totalSupply();
            expect(supply).to.equal(twoThirdsOLASBalance.add(1));
            // Withdraw what we can for the account, after which the balance is 2/3 of the initial balance
            await bu.connect(account).withdraw();
            expect(await olas.balanceOf(account.address)).to.equal(twoThirdsOLASBalance);
            // Now the balance is zero, since the rest of 1/3 tokens were burned
            supply = await bu.totalSupply();
            expect(supply).to.equal(0);

            // Now there is no releasable amount left
            amount = await bu.releasableAmount(account.address);
            expect(amount).to.equal(0);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Withdraw with revoke after the full lock period", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const owner = signers[0];
            const account = signers[1];

            // Approve owner for 1 OLAS by buOLAS that will be locked for account
            await olas.connect(owner).approve(bu.address, oneOLASBalance);

            // Define 3 years for the lock duration
            const numSteps = 3;
            await bu.connect(owner).createLockFor(account.address, oneOLASBalance, numSteps);

            // Move three years in time
            await helpers.time.increase(3 * oneYear + 100);
            
            // Revoke at this point of time
            await bu.connect(owner).revoke([account.address]);

            // The releasable amount must be the full locked amount, since the revoke took place after the lock time
            let amount = await bu.releasableAmount(account.address);
            expect(amount).to.equal(oneOLASBalance);
            // Same about buOLAS balance
            const balance = await bu.balanceOf(account.address);
            expect(balance).to.equal(oneOLASBalance);
            // Withdraw must return all the initially locked amount
            await bu.connect(account).withdraw();
            // The buOLAS balanceOf must be equal to the full initial amount after revoke
            expect(await olas.balanceOf(account.address)).to.equal(oneOLASBalance);

            // The supply must also be zero at this point of time
            const supply = await bu.totalSupply();
            expect(supply).to.equal(0);

            // There is also no releasable amount left
            amount = await bu.releasableAmount(account.address);
            expect(amount).to.equal(0);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Revoke after the full lock period, createLockFor for the same account and try to withdraw", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const owner = signers[0];
            const account = signers[1];

            // Approve owner for 2 OLAS by buOLAS, 1 OLAS will be locked on the account
            await olas.connect(owner).approve(bu.address, twoOLASBalance);

            // Define 3 years for the lock duration and create the lock
            const numSteps = 3;
            await bu.connect(owner).createLockFor(account.address, oneOLASBalance, numSteps);

            // Move three years in time
            // oneOLASBalance is fully unlocked at this point
            await helpers.time.increase(3 * oneYear + 100);
            
            // Revoke after the lock duration is expired
            // This revoke must never be performed in real situations since the account holder has a right
            // to all the funds initially locked
            await bu.connect(owner).revoke([account.address]);
            // Hence lockedBalance.totalAmount becomes 0 and lockedBalance.transferredAmount = oneOLASBalance
            // So createLockFor can be performed for the same account

            // Now createLockFor for the same account
            await bu.connect(owner).createLockFor(account.address, 3, numSteps);

            // Try to withdraw right away with the calculated releasable amount
            let amount = await bu.releasableAmount(account.address);
            // The amount would be -10^18.  However, due to the "unchecked" statement in the uint256 value, the amount will be as follows:
            // uint256Limit = 115792089237316195423570985008687907853269984665640564039456584007913129639936 =
            // = 2^256 - 1 - 10^18 (oneOLASBalance)
            expect(amount).to.equal(uint256Limit);
            // Withdraw will revert due to a number of requested OLAS token to be close to 2^256 (as pointed out above)
            // That much OLAS token total supply will not be minted in an observable timeframe (5+ billion years)
            await expect(
                bu.connect(account).withdraw()
            ).to.be.reverted;

            // Restore to the state of the snapshot
            await snapshot.restore();
        });
    });

    context("IERC20 functions", async function () {
        it("Check all the related functions", async function () {
            const deployer = signers[0].address;
            const user = signers[1].address;
            // Try to call transfer-related functions for buOLAS
            await expect(
                bu.approve(user, oneOLASBalance)
            ).to.be.revertedWithCustomError(bu, "NonTransferable");
            await expect(
                bu.allowance(deployer, user)
            ).to.be.revertedWithCustomError(bu, "NonTransferable");
            await expect(
                bu.transfer(user, oneOLASBalance)
            ).to.be.revertedWithCustomError(bu, "NonTransferable");
            await expect(
                bu.transferFrom(deployer, user, oneOLASBalance)
            ).to.be.revertedWithCustomError(bu, "NonTransferable");
        });
    });

    context("Time sensitive functions.", async function () {
        it("Should fail when creating a lock after the year of 2106", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const account = signers[1].address;
            await olas.approve(bu.address, oneOLASBalance);

            // Define 4 years for the lock duration
            const numSteps = 4;

            // Move time to the year 2106
            const year2106 = 4291821394;
            await helpers.time.increase(year2106);
            await expect(
                bu.createLockFor(account, oneOLASBalance, numSteps)
            ).to.be.revertedWithCustomError(bu, "Overflow");

            // Restore to the state of the snapshot
            await snapshot.restore();
        });
    });
});
