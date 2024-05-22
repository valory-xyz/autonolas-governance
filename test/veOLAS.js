/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("Voting Escrow OLAS", function () {
    let olas;
    let ve;
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
        ve = await VE.deploy(olas.address, "name", "symbol");
        await ve.deployed();
    });

    context("Locks", async function () {
        it("Check that never-supposed-to-happen zero parameter calls do not break anything", async function () {
            let result = await ve.getPastVotes(AddressZero, 0);
            expect(result).to.equal(0);

            result = await ve.getVotes(AddressZero);
            expect(result).to.equal(0);

            result = await ve.getPastTotalSupply(0);
            expect(result).to.equal(0);

            result = await ve.balanceOfAt(AddressZero, 0);
            expect(result).to.equal(0);

            result = await ve.totalSupplyAt(0);
            expect(result).to.equal(0);

            result = await ve.totalSupplyLockedAtT(0);
            expect(result).to.equal(0);
        });

        it("Interface support", async function () {
            // Checks for the compatibility with IERC165
            const interfaceIdIERC165 = "0x01ffc9a7";
            const checkInterfaceId = await ve.supportsInterface(interfaceIdIERC165);
            expect(checkInterfaceId).to.equal(true);
        });

        it("Should fail when creating a lock with zero value or wrong duration", async function () {
            await olas.approve(ve.address, oneOLASBalance);

            await expect(
                ve.createLock(0, 0)
            ).to.be.revertedWithCustomError(ve, "ZeroValue");

            await expect(
                ve.createLock(oneOLASBalance, 0)
            ).to.be.revertedWithCustomError(ve, "UnlockTimeIncorrect");

            await expect(
                ve.createLock(overflowNum96, oneWeek)
            ).to.be.revertedWithCustomError(ve, "Overflow");
        });

        it("Create lock", async function () {
            // Transfer 10 OLAS to signers[1]
            const owner = signers[1];
            await olas.transfer(owner.address, tenOLASBalance);

            // Approve signers[0] and signers[1] for 1 OLAS by voting escrow
            await olas.approve(ve.address, oneOLASBalance);
            await olas.connect(owner).approve(ve.address, oneOLASBalance);

            // Define 1 week for the lock duration
            const lockDuration = oneWeek; // 1 week from now

            // Balance should be zero before the lock
            expect(await ve.getVotes(owner.address)).to.equal(0);
            await ve.createLock(oneOLASBalance, lockDuration);
            await ve.connect(owner).createLock(oneOLASBalance, lockDuration);

            // Lock end is rounded by 1 week, as implemented by design
            const lockEnd = await ve.lockedEnd(owner.address);
            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            expect(Math.floor((block.timestamp + lockDuration) / oneWeek) * oneWeek).to.equal(lockEnd);

            // Get the account of the last user point
            const pv = await ve.getLastUserPoint(owner.address);
            expect(pv.balance).to.equal(oneOLASBalance);

            // Get the number of user points for owner and compare the balance of the last point
            const numAccountPoints = await ve.getNumUserPoints(owner.address);
            expect(numAccountPoints).to.equal(1);
            const pvLast = await ve.getUserPoint(owner.address, numAccountPoints - 1);
            expect(pvLast.balance).to.equal(pv.balance);

            // Balance is time-based, it changes slightly every fraction of a time
            // Use the second address for locked funds to compare
            const balanceDeployer = await ve.getVotes(signers[0].address);
            const balanceOwner = await ve.getVotes(owner.address);
            expect(balanceDeployer > 0).to.be.true;
            expect(balanceDeployer).to.equal(balanceOwner);
        });

        it("Create lock for", async function () {
            const owner = signers[0];
            const account = signers[1];

            // Approve owner for 1 OLAS by veOLAS
            await olas.connect(owner).approve(ve.address, oneOLASBalance);

            // Define 1 week for the lock duration
            const lockDuration = oneWeek; // 1 week from now

            // Balance should be zero before the lock
            expect(await ve.getVotes(account.address)).to.equal(0);
            // Try to create lock for the zero address
            await expect(
                ve.connect(owner).createLockFor(AddressZero, oneOLASBalance, lockDuration)
            ).to.be.revertedWithCustomError(ve, "ZeroAddress");

            // Lock for the account from the funds of the owner (approved for veOLAS)
            await ve.connect(owner).createLockFor(account.address, oneOLASBalance, lockDuration);

            // Lock end is rounded by 1 week, as implemented by design
            const lockEnd = await ve.lockedEnd(account.address);
            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            expect(Math.floor((block.timestamp + lockDuration) / oneWeek) * oneWeek).to.equal(lockEnd);

            // Get the account of the last user point
            const pv = await ve.getLastUserPoint(account.address);
            expect(pv.balance).to.equal(oneOLASBalance);

            // Get the number of user points for owner and compare the balance of the last point
            const numAccountPoints = await ve.getNumUserPoints(account.address);
            expect(numAccountPoints).to.equal(1);
            const pvLast = await ve.getUserPoint(account.address, numAccountPoints - 1);
            expect(pvLast.balance).to.equal(pv.balance);
        });

        it("Deposit for", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const deployer = signers[0];
            // Transfer 10 OLAS to signers[1]
            const owner = signers[1];
            await olas.transfer(owner.address, tenOLASBalance);

            // Approve deployer for 2 OLAS by voting escrow
            await olas.approve(ve.address, twoOLASBalance);
            // Approve owner for 1 OLAS by voting escrow
            await olas.connect(owner).approve(ve.address, oneOLASBalance);

            // Define 1 week for the lock duration
            const lockDuration = oneWeek; // 1 week from now

            // Try to deposit 1 OLAS for deployer without initially locked balance
            await expect(
                ve.depositFor(deployer.address, oneOLASBalance)
            ).to.be.revertedWithCustomError(ve, "NoValueLocked");

            // Create lock for the deployer
            await ve.createLock(oneOLASBalance, lockDuration);

            // Try to lock the remainder of 1 OLAS for deployer from the account that did not approve for veOLAS
            await expect(
                ve.connect(signers[2]).depositFor(deployer.address, oneOLASBalance)
            ).to.be.reverted;

            // Try to deposit zero value for deployer
            await expect(
                ve.depositFor(deployer.address, 0)
            ).to.be.revertedWithCustomError(ve, "ZeroValue");

            // Try to deposit a huge number
            await expect(
                ve.depositFor(deployer.address, overflowNum96)
            ).to.be.revertedWithCustomError(ve, "Overflow");

            // Deposit for the deployer from the
            await ve.connect(owner).depositFor(deployer.address, oneOLASBalance);

            // Check the balance of deployer (must be twice of his initial one)
            const balanceDeployer = await ve.balanceOf(deployer.address);
            expect(balanceDeployer).to.equal(twoOLASBalance);

            // Try to deposit 1 OLAS for deployer after its lock time hase expired
            await helpers.time.increase(oneWeek + 1000);

            await expect(
                ve.depositFor(deployer.address, oneOLASBalance)
            ).to.be.revertedWithCustomError(ve, "LockExpired");

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Should fail when creating a lock for more than 4 years", async function () {
            const fourYears = 4 * 365 * oneWeek / 7;
            await olas.approve(ve.address, oneOLASBalance);

            const lockDuration = fourYears + oneWeek; // 4 years and 1 week

            await expect(
                ve.createLock(oneOLASBalance, lockDuration)
            ).to.be.revertedWithCustomError(ve, "MaxUnlockTimeReached");
        });

        it("Should fail when creating a lock with already locked value", async function () {
            await olas.approve(ve.address, oneOLASBalance);
            const lockDuration = oneWeek;

            ve.createLock(oneOLASBalance, lockDuration);
            await expect(
                ve.createLock(oneOLASBalance, lockDuration)
            ).to.be.revertedWithCustomError(ve, "LockedValueNotZero");
        });

        it("Increase amount of lock", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            await olas.approve(ve.address, tenOLASBalance);
            const lockDuration = oneWeek;

            // Should fail if requires are not satisfied
            // No previous lock
            await expect(
                ve.increaseAmount(oneOLASBalance)
            ).to.be.revertedWithCustomError(ve, "NoValueLocked");

            // Now lock 1 OLAS
            ve.createLock(oneOLASBalance, lockDuration);
            // Increase by more than a zero
            await expect(
                ve.increaseAmount(0)
            ).to.be.revertedWithCustomError(ve, "ZeroValue");

            // Try to deposit a huge number
            await expect(
                ve.increaseAmount(overflowNum96)
            ).to.be.revertedWithCustomError(ve, "Overflow");

            // Add 1 OLAS more
            await ve.increaseAmount(oneOLASBalance);

            // Time forward to the lock expiration
            await helpers.time.increase(oneWeek);

            // Not possible to add to the expired lock
            await expect(
                ve.increaseAmount(oneOLASBalance)
            ).to.be.revertedWithCustomError(ve, "LockExpired");

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Increase amount of unlock time", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            await olas.approve(ve.address, tenOLASBalance);
            const lockDuration = oneWeek;

            // Should fail if requires are not satisfied
            // Nothing is locked
            await expect(
                ve.increaseUnlockTime(oneWeek)
            ).to.be.revertedWithCustomError(ve, "NoValueLocked");

            // Lock 1 OLAS
            await ve.createLock(oneOLASBalance, lockDuration);
            // Try to decrease the unlock time
            await expect(
                ve.increaseUnlockTime(lockDuration - 1)
            ).to.be.revertedWithCustomError(ve, "UnlockTimeIncorrect");

            await ve.increaseUnlockTime(lockDuration + oneWeek);

            // Try to increase unlock for the period of bigger than the max lock time
            await expect(
                ve.increaseUnlockTime(lockDuration + oneWeek * 300)
            ).to.be.revertedWithCustomError(ve, "MaxUnlockTimeReached");

            // Time forward to the lock expiration
            await helpers.time.increase(oneWeek + oneWeek);

            // Not possible to add to the expired lock
            await expect(
                ve.increaseUnlockTime(1)
            ).to.be.revertedWithCustomError(ve, "LockExpired");

            // Restore to the state of the snapshot
            await snapshot.restore();
        });
    });

    context("Withdraw", async function () {
        it("Withdraw", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Transfer 2 OLAS to signers[1] and approve the voting escrow for 1 OLAS
            const owner = signers[1];
            await olas.transfer(owner.address, tenOLASBalance);
            await olas.connect(owner).approve(ve.address, oneOLASBalance);

            // Lock 1 OLAS
            const lockDuration = 2 * oneWeek;
            await ve.connect(owner).createLock(oneOLASBalance, lockDuration);

            // Try withdraw early
            await expect(ve.connect(owner).withdraw()).to.be.revertedWithCustomError(ve, "LockNotExpired");
            // Move time close to the lock duration
            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            const roundedLockTime = Math.floor((block.timestamp + lockDuration) / oneWeek) * oneWeek;
            const adjustedLockDuration = roundedLockTime - block.timestamp;
            await helpers.time.increase(adjustedLockDuration - 100);

            // Try withdraw about the unlock time, but not quite there yet
            await expect(ve.connect(owner).withdraw()).to.be.revertedWithCustomError(ve, "LockNotExpired");

            // Move time after the lock duration
            await helpers.time.increase(200);

            // Now withdraw must work
            await ve.connect(owner).withdraw();
            expect(await olas.balanceOf(owner.address)).to.equal(tenOLASBalance);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });
    });

    context("Balance and supply", async function () {
        it("Supply at", async function () {
            // Transfer 10 OLAS worth of OLAS to signers[1]
            const deployer = signers[0];
            const account = signers[1];
            await olas.transfer(account.address, tenOLASBalance);

            // Approve deployer and account for 1 OLAS by voting escrow
            await olas.approve(ve.address, oneOLASBalance);
            await olas.connect(account).approve(ve.address, tenOLASBalance);

            // Initial total supply must be 0
            expect(await ve.totalSupply()).to.equal(0);

            // Define 1 week for the lock duration
            const lockDuration = oneWeek; // 1 week from now

            // Create locks for both addresses deployer and account
            await ve.createLock(oneOLASBalance, lockDuration);
            await ve.connect(account).createLock(twoOLASBalance, lockDuration);

            // Balance is time-based, it changes slightly every fraction of a time
            // Use both balances to check for the supply
            let balanceDeployer = await ve.getVotes(deployer.address);
            let balanceAccount = await ve.getVotes(account.address);
            let supply = await ve.totalSupplyLocked();
            let sumBalance = BigInt(balanceAccount) + BigInt(balanceDeployer);
            expect(supply).to.equal(sumBalance.toString());

            const blockNumber = await ethers.provider.getBlockNumber();
            // Check the total supply in pure OLAS against the locked balance in OLAS as well (not veOLAS)
            balanceDeployer = await ve.balanceOfAt(deployer.address, blockNumber);
            balanceAccount = await ve.balanceOfAt(account.address, blockNumber);
            supply = await ve.totalSupplyAt(blockNumber);
            sumBalance = BigInt(balanceAccount) + BigInt(balanceDeployer);
            expect(supply).to.equal(sumBalance.toString());
        });

        it("Checkpoint", async function () {
            const user = signers[1].address;
            // We don't have any points at the beginning
            let numPoints = await ve.totalNumPoints();
            expect(numPoints).to.equal(0);

            // Checkpoint writes point and increases their global counter
            await ve.checkpoint();
            numPoints = await ve.totalNumPoints();
            expect(numPoints).to.equal(1);

            // Try to get past total voting supply of a block number in the future
            const blockNumber = await ethers.provider.getBlockNumber();
            await expect(
                ve.getPastTotalSupply(blockNumber + 10)
            ).to.be.revertedWithCustomError(ve, "WrongBlockNumber");

            // Try to get past total supply of a block number in the future
            await expect(
                ve.getPastVotes(user, blockNumber + 20)
            ).to.be.revertedWithCustomError(ve, "WrongBlockNumber");
        });

        it("Checkpoint with points of inactivity", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Approve deployer and account for 1 OLAS by voting escrow
            await olas.approve(ve.address, oneOLASBalance);

            // Lock for four years
            const lockDuration = 4 * 365 * oneWeek / 7;

            // Create locks for both addresses deployer and account
            await ve.createLock(oneOLASBalance, lockDuration);

            // Move 10 weeks in time
            for (let i = 0; i < 10; ++i) {
                await helpers.time.increase(oneWeek + 10);
            }

            // Checkpoint writes point and increases their global counter
            await ve.checkpoint();

            // The checkpoints created during the inactivity weeks have the same block number but a different timestamp
            const point1 = await ve.mapSupplyPoints(3);
            const blockNumber1 = point1.blockNumber;
            const timeStamp1 = point1.ts;
            const point2 = await ve.mapSupplyPoints(7);
            const blockNumber2 = point2.blockNumber;
            const timeStamp2 = point2.ts;
            expect(blockNumber1).to.equal(blockNumber2);
            expect(timeStamp1).not.equal(timeStamp2);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Getting past votes and supply", async function () {
            // Transfer 10 OLAS worth of OLAS to signers[1]
            const deployer = signers[0];
            const owner = signers[1];
            await olas.transfer(owner.address, tenOLASBalance);

            // Approve signers[0] and signers[1] for 1 OLAS by voting escrow
            await olas.approve(ve.address, tenOLASBalance);
            await olas.connect(owner).approve(ve.address, tenOLASBalance);

            // Define 1 week for the lock duration
            let lockDuration = oneWeek;

            // Create and increase locks for both addresses signers[0] and signers[1]
            await ve.createLock(twoOLASBalance, lockDuration);
            await ve.increaseAmount(oneOLASBalance);
            let blockNumber = await ethers.provider.getBlockNumber();
            await ve.connect(owner).createLock(twoOLASBalance, lockDuration);
            await ve.connect(owner).increaseAmount(oneOLASBalance);
            await ve.connect(owner).increaseAmount(oneOLASBalance);

            // Get past votes of the owner (bug resolved in wveOLAS)
            const votesOwner = await ve.getPastVotes(owner.address, blockNumber);
            expect(votesOwner).to.greaterThan(0);

            // Get past voting supply from the same block number
            const supply = await ve.getPastTotalSupply(blockNumber);
            // They must be equal with the deployer voting power at that time
            const votesDeployer = await ve.getPastVotes(deployer.address, blockNumber);
            expect(Number(supply)).to.equal(Number(votesDeployer));

            // Try to get voting supply power at time in the future
            blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            const supplyAt = await ve.totalSupplyLockedAtT(block.timestamp + oneWeek + 1000);
            expect(Number(supplyAt)).to.equal(0);
        });
    });

    context("IERC20 and IVotes functions", async function () {
        it("Check all the related functions", async function () {
            const deployer = signers[0].address;
            const user = signers[1].address;
            // Approve signers[0] for 1 OLAS by voting escrow
            await olas.approve(ve.address, oneOLASBalance);

            // Initial total supply must be 0
            expect(await ve.totalSupply()).to.equal(0);

            // Define 1 week for the lock duration
            const lockDuration = oneWeek; // 1 week from now

            // Create locks for both addresses signers[0] and signers[1]
            await ve.createLock(oneOLASBalance, lockDuration);

            // Try to call transfer-related functions for veOLAS
            await expect(
                ve.approve(user, oneOLASBalance)
            ).to.be.revertedWithCustomError(ve, "NonTransferable");
            await expect(
                ve.allowance(deployer, user)
            ).to.be.revertedWithCustomError(ve, "NonTransferable");
            await expect(
                ve.transfer(user, oneOLASBalance)
            ).to.be.revertedWithCustomError(ve, "NonTransferable");
            await expect(
                ve.transferFrom(deployer, user, oneOLASBalance)
            ).to.be.revertedWithCustomError(ve, "NonTransferable");

            // Try to call delegate-related functions for veOLAS
            await expect(
                ve.delegates(user)
            ).to.be.revertedWithCustomError(ve, "NonDelegatable");
            await expect(
                ve.delegate(deployer)
            ).to.be.revertedWithCustomError(ve, "NonDelegatable");
            const rv = "0x" + "0".repeat(64);
            await expect(
                ve.delegateBySig(deployer, 0, 0, 0, rv, rv)
            ).to.be.revertedWithCustomError(ve, "NonDelegatable");
        });
    });
});
