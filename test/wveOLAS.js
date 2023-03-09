/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Wrapped Voting Escrow OLAS", function () {
    let olas;
    let ve;
    let wve;
    let signers;
    const initialMint = "1000000000000000000000000"; // 1000000
    const oneWeek = 7 * 86400;
    const oneOLABalance = ethers.utils.parseEther("1");
    const twoOLABalance = ethers.utils.parseEther("2");
    const tenOLABalance = ethers.utils.parseEther("10");
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

        const WVE = await ethers.getContractFactory("wveOLAS");
        const wveProxy = await WVE.deploy(ve.address);
        await wveProxy.deployed();

        wve = await ethers.getContractAt("veOLAS", wveProxy.address);
    });

    context("Locks", async function () {
        it("Should fail when deploying with the zero address", async function () {
            const WVE = await ethers.getContractFactory("wveOLAS");
            await expect(
                WVE.deploy(AddressZero)
            ).to.be.revertedWith("ZeroVEOLASAddress");
        });

        it("Check that never-supposed-to-happen zero parameter calls do not break anything", async function () {
            let result = await wve.getPastVotes(AddressZero, 0);
            expect(result).to.equal(0);

            result = await ve.getVotes(AddressZero);
            expect(result).to.equal(0);

            result = await wve.getPastTotalSupply(0);
            expect(result).to.equal(0);

            result = await wve.balanceOfAt(AddressZero, 0);
            expect(result).to.equal(0);

            result = await wve.totalSupplyAt(0);
            expect(result).to.equal(0);

            await expect(
                wve.totalSupplyLockedAtT(0)
            ).to.be.reverted;
        });

        it("Interface support", async function () {
            // Checks for the compatibility with IERC165
            const interfaceIdIERC165 = "0x01ffc9a7";
            const checkInterfaceId = await ve.supportsInterface(interfaceIdIERC165);
            expect(checkInterfaceId).to.equal(true);
        });

        it("Should fail when creating a lock with zero value or wrong duration", async function () {
            await olas.approve(ve.address, oneOLABalance);

            await expect(
                ve.createLock(0, 0)
            ).to.be.revertedWith("ZeroValue");

            await expect(
                ve.createLock(oneOLABalance, 0)
            ).to.be.revertedWith("UnlockTimeIncorrect");

            await expect(
                ve.createLock(overflowNum96, oneWeek)
            ).to.be.revertedWith("Overflow");
        });

        it("Create lock", async function () {
            // Transfer 10 OLAS to signers[1]
            const owner = signers[1];
            await olas.transfer(owner.address, tenOLABalance);

            // Approve signers[0] and signers[1] for 1 OLAS by voting escrow
            await olas.approve(ve.address, oneOLABalance);
            await olas.connect(owner).approve(ve.address, oneOLABalance);

            // Define 1 week for the lock duration
            const lockDuration = oneWeek; // 1 week from now

            // Balance should be zero before the lock
            expect(await ve.getVotes(owner.address)).to.equal(0);
            await ve.createLock(oneOLABalance, lockDuration);
            await ve.connect(owner).createLock(oneOLABalance, lockDuration);

            // Lock end is rounded by 1 week, as implemented by design
            const lockEnd = await ve.lockedEnd(owner.address);
            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            expect(Math.floor((block.timestamp + lockDuration) / oneWeek) * oneWeek).to.equal(lockEnd);

            // Get the account of the last user point
            const pv = await ve.getLastUserPoint(owner.address);
            expect(pv.balance).to.equal(oneOLABalance);

            // Get the number of user points for owner and compare the balance of the last point
            const numAccountPoints = await ve.getNumUserPoints(owner.address);
            expect(numAccountPoints).to.equal(1);
            const pvLast = await wve.getUserPoint(owner.address, numAccountPoints - 1);
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
            await olas.connect(owner).approve(ve.address, oneOLABalance);

            // Define 1 week for the lock duration
            const lockDuration = oneWeek; // 1 week from now

            // Balance should be zero before the lock
            expect(await ve.getVotes(account.address)).to.equal(0);
            // Try to create lock for the zero address
            await expect(
                ve.connect(owner).createLockFor(AddressZero, oneOLABalance, lockDuration)
            ).to.be.revertedWith("ZeroAddress");

            // Lock for the account from the funds of the owner (approved for veOLAS)
            await ve.connect(owner).createLockFor(account.address, oneOLABalance, lockDuration);

            // Lock end is rounded by 1 week, as implemented by design
            const lockEnd = await ve.lockedEnd(account.address);
            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            expect(Math.floor((block.timestamp + lockDuration) / oneWeek) * oneWeek).to.equal(lockEnd);

            // Get the account of the last user point
            const pv = await ve.getLastUserPoint(account.address);
            expect(pv.balance).to.equal(oneOLABalance);

            // Get the number of user points for owner and compare the balance of the last point
            const numAccountPoints = await ve.getNumUserPoints(account.address);
            expect(numAccountPoints).to.equal(1);
            const pvLast = await wve.getUserPoint(account.address, numAccountPoints - 1);
            expect(pvLast.balance).to.equal(pv.balance);
        });

        it("Deposit for", async function () {
            const deployer = signers[0];
            // Transfer 10 OLAS to signers[1]
            const owner = signers[1];
            await olas.transfer(owner.address, tenOLABalance);

            // Approve deployer for 2 OLAS by voting escrow
            await olas.approve(ve.address, twoOLABalance);
            // Approve owner for 1 OLAS by voting escrow
            await olas.connect(owner).approve(ve.address, oneOLABalance);

            // Define 1 week for the lock duration
            const lockDuration = oneWeek; // 1 week from now

            // Try to deposit 1 OLAS for deployer without initially locked balance
            await expect(
                ve.depositFor(deployer.address, oneOLABalance)
            ).to.be.revertedWith("NoValueLocked");

            // Create lock for the deployer
            await ve.createLock(oneOLABalance, lockDuration);

            // Try to lock the remainder of 1 OLAS for deployer from the account that did not approve for veOLAS
            await expect(
                ve.connect(signers[2]).depositFor(deployer.address, oneOLABalance)
            ).to.be.reverted;

            // Try to deposit zero value for deployer
            await expect(
                ve.depositFor(deployer.address, 0)
            ).to.be.revertedWith("ZeroValue");

            // Try to deposit a huge number
            await expect(
                ve.depositFor(deployer.address, overflowNum96)
            ).to.be.revertedWith("Overflow");

            // Deposit for the deployer from the
            await ve.connect(owner).depositFor(deployer.address, oneOLABalance);

            // Check the balance of deployer (must be twice of his initial one)
            const balanceDeployer = await ve.balanceOf(deployer.address);
            expect(balanceDeployer).to.equal(twoOLABalance);

            // Try to deposit 1 OLAS for deployer after its lock time hase expired
            ethers.provider.send("evm_increaseTime", [oneWeek + 1000]);
            ethers.provider.send("evm_mine");
            await expect(
                ve.depositFor(deployer.address, oneOLABalance)
            ).to.be.revertedWith("LockExpired");
        });

        it("Should fail when creating a lock for more than 4 years", async function () {
            const fourYears = 4 * 365 * oneWeek / 7;
            await olas.approve(ve.address, oneOLABalance);

            const lockDuration = fourYears + oneWeek; // 4 years and 1 week

            await expect(
                ve.createLock(oneOLABalance, lockDuration)
            ).to.be.revertedWith("MaxUnlockTimeReached");
        });

        it("Should fail when creating a lock with already locked value", async function () {
            await olas.approve(ve.address, oneOLABalance);
            const lockDuration = oneWeek;

            ve.createLock(oneOLABalance, lockDuration);
            await expect(
                ve.createLock(oneOLABalance, lockDuration)
            ).to.be.revertedWith("LockedValueNotZero");
        });

        it("Increase amount of lock", async function () {
            await olas.approve(ve.address, tenOLABalance);
            const lockDuration = oneWeek;

            // Should fail if requires are not satisfied
            // No previous lock
            await expect(
                ve.increaseAmount(oneOLABalance)
            ).to.be.revertedWith("NoValueLocked");

            // Now lock 1 OLAS
            ve.createLock(oneOLABalance, lockDuration);
            // Increase by more than a zero
            await expect(
                ve.increaseAmount(0)
            ).to.be.revertedWith("ZeroValue");

            // Try to deposit a huge number
            await expect(
                ve.increaseAmount(overflowNum96)
            ).to.be.revertedWith("Overflow");

            // Add 1 OLAS more
            await ve.increaseAmount(oneOLABalance);

            // Time forward to the lock expiration
            ethers.provider.send("evm_increaseTime", [oneWeek]);
            ethers.provider.send("evm_mine");

            // Not possible to add to the expired lock
            await expect(
                ve.increaseAmount(oneOLABalance)
            ).to.be.revertedWith("LockExpired");
        });

        it("Increase amount of unlock time", async function () {
            await olas.approve(ve.address, tenOLABalance);
            const lockDuration = oneWeek;

            // Should fail if requires are not satisfied
            // Nothing is locked
            await expect(
                ve.increaseUnlockTime(oneWeek)
            ).to.be.revertedWith("NoValueLocked");

            // Lock 1 OLAS
            await ve.createLock(oneOLABalance, lockDuration);
            // Try to decrease the unlock time
            await expect(
                ve.increaseUnlockTime(lockDuration - 1)
            ).to.be.revertedWith("UnlockTimeIncorrect");

            await ve.increaseUnlockTime(lockDuration + oneWeek);

            // Try to increase unlock for the period of bigger than the max lock time
            await expect(
                ve.increaseUnlockTime(lockDuration + oneWeek * 300)
            ).to.be.revertedWith("MaxUnlockTimeReached");

            // Time forward to the lock expiration
            ethers.provider.send("evm_increaseTime", [oneWeek + oneWeek]);
            ethers.provider.send("evm_mine");

            // Not possible to add to the expired lock
            await expect(
                ve.increaseUnlockTime(1)
            ).to.be.revertedWith("LockExpired");
        });
    });

    context("Withdraw", async function () {
        it("Withdraw", async function () {
            // Transfer 2 OLAS to signers[1] and approve the voting escrow for 1 OLAS
            const owner = signers[1];
            await olas.transfer(owner.address, tenOLABalance);
            await olas.connect(owner).approve(ve.address, oneOLABalance);

            // Lock 1 OLAS
            const lockDuration = 2 * oneWeek;
            await ve.connect(owner).createLock(oneOLABalance, lockDuration);

            // Try withdraw early
            await expect(ve.connect(owner).withdraw()).to.be.revertedWith("LockNotExpired");
            // Move time close to the lock duration
            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            const roundedLockTime = Math.floor((block.timestamp + lockDuration) / oneWeek) * oneWeek;
            const adjustedLockDuration = roundedLockTime - block.timestamp;
            ethers.provider.send("evm_increaseTime", [adjustedLockDuration - 100]);
            ethers.provider.send("evm_mine");

            // Try withdraw about the unlock time, but not quite there yet
            await expect(ve.connect(owner).withdraw()).to.be.revertedWith("LockNotExpired");

            // Move time after the lock duration
            ethers.provider.send("evm_increaseTime", [200]);
            ethers.provider.send("evm_mine");

            // Now withdraw must work
            await ve.connect(owner).withdraw();
            expect(await olas.balanceOf(owner.address)).to.equal(tenOLABalance);
        });
    });

    context("Balance and supply", async function () {
        it("Supply at", async function () {
            // Transfer 10 OLAS worth of OLAS to signers[1]
            const deployer = signers[0];
            const account = signers[1];
            await olas.transfer(account.address, tenOLABalance);

            // Approve deployer and account for 1 and 10 OLAS by voting escrow
            await olas.approve(ve.address, oneOLABalance);
            await olas.connect(account).approve(ve.address, tenOLABalance);

            // Initial total supply must be 0
            expect(await ve.totalSupply()).to.equal(0);

            // Define 1 week for the lock duration
            const lockDuration = oneWeek; // 1 week from now

            // Create locks for both addresses deployer and account
            await ve.createLock(oneOLABalance, lockDuration);
            await ve.connect(account).createLock(twoOLABalance, lockDuration);

            // Balance is time-based, it changes slightly every fraction of a time
            // Use both balances to check for the supply
            let balanceDeployer = await ve.getVotes(deployer.address);
            let balanceAccount = await ve.getVotes(account.address);
            let supply = await ve.totalSupplyLocked();
            let sumBalance = BigInt(balanceAccount) + BigInt(balanceDeployer);
            expect(supply).to.equal(sumBalance.toString());

            const blockNumber = await ethers.provider.getBlockNumber();
            // Check the total supply in pure OLAS against the locked balance in OLAS as well (not veOLAS)
            balanceDeployer = await wve.balanceOfAt(deployer.address, blockNumber);
            balanceAccount = await wve.balanceOfAt(account.address, blockNumber);
            supply = await ve.totalSupplyAt(blockNumber);
            sumBalance = BigInt(balanceAccount) + BigInt(balanceDeployer);
            expect(supply).to.equal(sumBalance.toString());
        });

        it("Checkpoint", async function () {
            const user = signers[1];
            // We don't have any points at the beginning
            let numPoints = await ve.totalNumPoints();
            expect(numPoints).to.equal(0);

            // Checkpoint writes point and increases their global counter
            await ve.checkpoint();
            numPoints = await ve.totalNumPoints();
            expect(numPoints).to.equal(1);

            // Try to get past total voting supply of a block number in the future
            let blockNumber = await ethers.provider.getBlockNumber("latest");
            await expect(
                wve.getPastTotalSupply(blockNumber + 10)
            ).to.be.revertedWith("WrongBlockNumber");

            // Transfer OLAS to the user
            await olas.transfer(user.address, tenOLABalance);
            // Approve user for 1 OLAS by voting escrow
            await olas.connect(user).approve(ve.address, oneOLABalance);
            // Define 1 week for the lock duration
            const lockDuration = oneWeek; // 1 week from now
            // Create locks for both addresses deployer and account
            await ve.connect(user).createLock(oneOLABalance, lockDuration);
            blockNumber = await ethers.provider.getBlockNumber("latest");

            // Try to get past votes of a block number in the future
            await expect(
                wve.getPastVotes(user.address, blockNumber + 20)
            ).to.be.revertedWith("WrongBlockNumber");
        });

        it("Checkpoint with points of inactivity", async function () {
            // Approve deployer and account for 1 OLAS by voting escrow
            await olas.approve(ve.address, oneOLABalance);

            // Lock for four years
            const lockDuration = 4 * 365 * oneWeek / 7;

            // Create locks for both addresses deployer and account
            await ve.createLock(oneOLABalance, lockDuration);

            // Move 10 weeks in time
            for (let i = 0; i < 10; ++i) {
                ethers.provider.send("evm_increaseTime", [oneWeek + 10]);
                ethers.provider.send("evm_mine");
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
        });

        it("Getting past votes and supply", async function () {
            // Transfer 10 OLAS worth of OLAS to signers[1]
            const deployer = signers[0];
            const owner = signers[1];
            await olas.transfer(owner.address, tenOLABalance);

            // Approve signers[0] and signers[1] for 10 OLAS by voting escrow
            await olas.approve(ve.address, tenOLABalance);
            await olas.connect(owner).approve(ve.address, tenOLABalance);

            // Define 1 week for the lock duration
            let lockDuration = oneWeek;

            // Create and increase locks for both addresses signers[0] and signers[1]
            await ve.createLock(twoOLABalance, lockDuration);
            await ve.increaseAmount(oneOLABalance);
            await ve.connect(owner).createLock(twoOLABalance, lockDuration);
            await ve.connect(owner).increaseAmount(oneOLABalance);
            await ve.connect(owner).increaseAmount(oneOLABalance);
            let blockNumber = await ethers.provider.getBlockNumber("latest");

            // Get past votes of the owner
            const votesOwner = ethers.BigNumber.from(await wve.getPastVotes(owner.address, blockNumber));
            expect(Number(votesOwner)).to.greaterThan(0);

            // Get past voting supply from the same block number
            const supply = ethers.BigNumber.from(await ve.getPastTotalSupply(blockNumber));
            // The sum of deployer and owner voting power must be equal with supply voting power at that time
            const votesDeployer = ethers.BigNumber.from(await wve.getPastVotes(deployer.address, blockNumber));
            expect(supply).to.equal(votesDeployer.add(votesOwner));

            // Try to get voting supply power at time in the future
            blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            const supplyAt = ethers.BigNumber.from(await wve.totalSupplyLockedAtT(block.timestamp + oneWeek + 1000));
            expect(supplyAt).to.equal(0);
        });
    });

    context("Wrapper related", async function () {
        it("Should fail when calling a function that must be called from the original veOLAS", async function () {
            await expect(
                wve.createLock(oneOLABalance, oneWeek)
            ).to.be.revertedWith("ImplementedIn");
        });

        it("Balance with a block number lower than a zero user point block number returns zero value", async function () {
            // Transfer 10 OLAS worth of OLAS to signers[1]
            const deployer = signers[0];
            await olas.transfer(deployer.address, tenOLABalance);

            // Approve signers[0] for 10 OLAS by voting escrow
            await olas.approve(ve.address, tenOLABalance);

            const block = await ethers.provider.getBlock("latest");
            // Create lock for signers[0]
            await ve.createLock(twoOLABalance, oneWeek);

            // Try to get the balance value before the lock
            const balance = await wve.balanceOfAt(deployer.address, block.number);
            expect(balance).to.equal(0);
        });
    });
});
