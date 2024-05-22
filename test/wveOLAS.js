/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("Wrapped Voting Escrow OLAS", function () {
    let olas;
    let ve;
    let wve;
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

        const WVE = await ethers.getContractFactory("wveOLAS");
        wve = await WVE.deploy(ve.address, olas.address);
        await wve.deployed();
    });

    context("Locks", async function () {
        it("Should fail when deploying with the zero address", async function () {
            const WVE = await ethers.getContractFactory("wveOLAS");
            await expect(
                WVE.deploy(AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(wve, "ZeroAddress");

            await expect(
                WVE.deploy(ve.address, AddressZero)
            ).to.be.revertedWithCustomError(wve, "ZeroAddress");
        });

        it("Check that never-supposed-to-happen zero parameter calls do not break anything", async function () {
            let result = await wve.getPastVotes(AddressZero, 0);
            expect(result).to.equal(0);

            result = await wve.getVotes(AddressZero);
            expect(result).to.equal(0);

            await expect(
                wve.getPastTotalSupply(0)
            ).to.be.reverted;

            result = await wve.balanceOfAt(AddressZero, 0);
            expect(result).to.equal(0);

            result = await wve.totalSupplyAt(0);
            expect(result).to.equal(0);

            await expect(
                wve.totalSupplyLockedAtT(0)
            ).to.be.revertedWithCustomError(wve, "WrongTimestamp");
        });

        it("Interface support", async function () {
            // Checks for the compatibility with IERC165
            const interfaceIdIERC165 = "0x01ffc9a7";
            const checkInterfaceId = await wve.supportsInterface(interfaceIdIERC165);
            expect(checkInterfaceId).to.equal(true);
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
            expect(await wve.getVotes(owner.address)).to.equal(0);
            await ve.createLock(oneOLASBalance, lockDuration);
            await ve.connect(owner).createLock(oneOLASBalance, lockDuration);

            // Lock end is rounded by 1 week, as implemented by design
            const lockEnd = await wve.lockedEnd(owner.address);
            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            expect(Math.floor((block.timestamp + lockDuration) / oneWeek) * oneWeek).to.equal(lockEnd);

            // Get the account of the last user point
            const pv = await wve.getLastUserPoint(owner.address);
            expect(pv.balance).to.equal(oneOLASBalance);

            // Get the number of user points for owner and compare the balance of the last point
            const numAccountPoints = await wve.getNumUserPoints(owner.address);
            expect(numAccountPoints).to.equal(1);
            const pvLast = await wve.getUserPoint(owner.address, numAccountPoints - 1);
            expect(pvLast.balance).to.equal(pv.balance);

            // Balance is time-based, it changes slightly every fraction of a time
            // Use the second address for locked funds to compare
            const balanceDeployer = await wve.getVotes(signers[0].address);
            const balanceOwner = await wve.getVotes(owner.address);
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
            expect(await wve.getVotes(account.address)).to.equal(0);
            // Try to create lock for the zero address
            await expect(
                ve.connect(owner).createLockFor(AddressZero, oneOLASBalance, lockDuration)
            ).to.be.revertedWithCustomError(ve, "ZeroAddress");

            // Lock for the account from the funds of the owner (approved for veOLAS)
            await ve.connect(owner).createLockFor(account.address, oneOLASBalance, lockDuration);

            // Lock end is rounded by 1 week, as implemented by design
            const lockEnd = await wve.lockedEnd(account.address);
            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            expect(Math.floor((block.timestamp + lockDuration) / oneWeek) * oneWeek).to.equal(lockEnd);

            // Get the account of the last user point
            const pv = await wve.getLastUserPoint(account.address);
            expect(pv.balance).to.equal(oneOLASBalance);

            // Get the number of user points for owner and compare the balance of the last point
            const numAccountPoints = await wve.getNumUserPoints(account.address);
            expect(numAccountPoints).to.equal(1);
            const pvLast = await wve.getUserPoint(account.address, numAccountPoints - 1);
            expect(pvLast.balance).to.equal(pv.balance);
        });

        it("Deposit for", async function () {
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
            const balanceDeployer = await wve.balanceOf(deployer.address);
            expect(balanceDeployer).to.equal(twoOLASBalance);

            // Try to deposit 1 OLAS for deployer after its lock time hase expired
            await helpers.time.increase(oneWeek + 1000);

            await expect(
                ve.depositFor(deployer.address, oneOLASBalance)
            ).to.be.revertedWithCustomError(ve, "LockExpired");
        });
    });

    context("Balance and supply", async function () {
        it("Supply at", async function () {
            // Transfer 10 OLAS worth of OLAS to signers[1]
            const deployer = signers[0];
            const account = signers[1];
            await olas.transfer(account.address, tenOLASBalance);

            // Approve deployer and account for 1 and 10 OLAS by voting escrow
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
            let balanceDeployer = await wve.getVotes(deployer.address);
            let balanceAccount = await wve.getVotes(account.address);
            let supply = await wve.totalSupplyLocked();
            let sumBalance = BigInt(balanceAccount) + BigInt(balanceDeployer);
            expect(supply).to.equal(sumBalance.toString());

            const blockNumber = await ethers.provider.getBlockNumber();
            // Check the total supply in pure OLAS against the locked balance in OLAS as well (not veOLAS)
            balanceDeployer = await wve.balanceOfAt(deployer.address, blockNumber);
            balanceAccount = await wve.balanceOfAt(account.address, blockNumber);
            supply = await wve.totalSupplyAt(blockNumber);
            sumBalance = BigInt(balanceAccount) + BigInt(balanceDeployer);
            expect(supply).to.equal(sumBalance.toString());
        });

        it("Checkpoint", async function () {
            const user = signers[1];
            // We don't have any points at the beginning
            let numPoints = await wve.totalNumPoints();
            expect(numPoints).to.equal(0);

            // Checkpoint writes point and increases their global counter
            await ve.checkpoint();
            numPoints = await wve.totalNumPoints();
            expect(numPoints).to.equal(1);

            // Try to get past total voting supply of a block number in the future
            let blockNumber = await ethers.provider.getBlockNumber("latest");
            await expect(
                wve.getPastTotalSupply(blockNumber + 10)
            ).to.be.revertedWithCustomError(ve, "WrongBlockNumber");

            // Transfer OLAS to the user
            await olas.transfer(user.address, tenOLASBalance);
            // Approve user for 1 OLAS by voting escrow
            await olas.connect(user).approve(ve.address, oneOLASBalance);
            // Define 1 week for the lock duration
            const lockDuration = oneWeek; // 1 week from now
            // Create locks for both addresses deployer and account
            await ve.connect(user).createLock(oneOLASBalance, lockDuration);
            blockNumber = await ethers.provider.getBlockNumber("latest");

            // Try to get past votes of a block number in the future
            await expect(
                wve.getPastVotes(user.address, blockNumber + 20)
            ).to.be.revertedWithCustomError(ve, "WrongBlockNumber");
        });

        it("Getting past votes and supply", async function () {
            // Transfer 10 OLAS worth of OLAS to signers[1]
            const deployer = signers[0];
            const owner = signers[1];
            await olas.transfer(owner.address, tenOLASBalance);

            // Approve signers[0] and signers[1] for 10 OLAS by voting escrow
            await olas.approve(ve.address, tenOLASBalance);
            await olas.connect(owner).approve(ve.address, tenOLASBalance);

            // Define 1 week for the lock duration
            let lockDuration = oneWeek;

            // Create and increase locks for both addresses signers[0] and signers[1]
            await ve.createLock(twoOLASBalance, lockDuration);
            await ve.increaseAmount(oneOLASBalance);
            let blockNumber = await ethers.provider.getBlockNumber("latest");
            await ve.connect(owner).createLock(twoOLASBalance, lockDuration);
            await ve.connect(owner).increaseAmount(oneOLASBalance);
            await ve.connect(owner).increaseAmount(oneOLASBalance);

            // The past votes before the lock must be zero
            let votesOwner = ethers.BigNumber.from(await wve.getPastVotes(owner.address, blockNumber));
            expect(votesOwner).to.equal(0);

            // Get past votes of the owner after the lock
            blockNumber = await ethers.provider.getBlockNumber("latest");
            votesOwner = ethers.BigNumber.from(await wve.getPastVotes(owner.address, blockNumber));
            expect(votesOwner).to.greaterThan(0);

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

            // Get the zero supply point
            const sPoint = await wve.mapSupplyPoints(0);
            expect(sPoint.ts).to.greaterThan(0);
            expect(sPoint.blockNumber).to.greaterThan(0);

            // Get the zero ts slope change
            const slopeChange = await wve.mapSlopeChanges(0);
            expect(slopeChange).to.equal(0);
        });
    });

    context("Wrapper related", async function () {
        it("Should fail when calling a function that must be called from the original veOLAS", async function () {
            const wveProxy = await ethers.getContractAt("veOLAS", wve.address);
            await expect(
                wveProxy.createLock(oneOLASBalance, oneWeek)
            ).to.be.revertedWithCustomError(wve, "ImplementedIn");
        });

        it("Balance with a block number lower than a zero user point block number returns zero value", async function () {
            // Transfer 10 OLAS worth of OLAS to signers[1]
            const deployer = signers[0];
            await olas.transfer(deployer.address, tenOLASBalance);

            // Approve signers[0] for 10 OLAS by voting escrow
            await olas.approve(ve.address, tenOLASBalance);

            const block = await ethers.provider.getBlock("latest");
            // Create lock for signers[0]
            await ve.createLock(twoOLASBalance, oneWeek);

            // Try to get the balance value before the lock
            const balance = await wve.balanceOfAt(deployer.address, block.number);
            expect(balance).to.equal(0);
        });
    });

    context("IERC20 and IVotes functions", async function () {
        it("Check all the related functions", async function () {
            const deployer = signers[0].address;
            const user = signers[1].address;
            // Approve signers[0] for 1 OLAS by voting escrow
            await olas.approve(ve.address, oneOLASBalance);

            // Initial total supply must be 0
            expect(await wve.totalSupply()).to.equal(0);

            // Define 1 week for the lock duration
            const lockDuration = oneWeek; // 1 week from now

            // Create locks for both addresses signers[0] and signers[1]
            await ve.createLock(oneOLASBalance, lockDuration);

            // Try to call transfer-related functions for veOLAS
            await expect(
                wve.approve(user, oneOLASBalance)
            ).to.be.revertedWithCustomError(wve, "NonTransferable");
            await expect(
                wve.allowance(deployer, user)
            ).to.be.revertedWithCustomError(wve, "NonTransferable");
            await expect(
                wve.transfer(user, oneOLASBalance)
            ).to.be.revertedWithCustomError(wve, "NonTransferable");
            await expect(
                wve.transferFrom(deployer, user, oneOLASBalance)
            ).to.be.revertedWithCustomError(wve, "NonTransferable");

            // Try to call delegate-related functions for veOLAS
            await expect(
                wve.delegates(user)
            ).to.be.revertedWithCustomError(wve, "NonDelegatable");
            await expect(
                wve.delegate(deployer)
            ).to.be.revertedWithCustomError(wve, "NonDelegatable");
            const rv = "0x" + "0".repeat(64);
            await expect(
                wve.delegateBySig(deployer, 0, 0, 0, rv, rv)
            ).to.be.revertedWithCustomError(wve, "NonDelegatable");
        });
    });
});
