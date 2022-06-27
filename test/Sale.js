/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Sale contract", function () {
    let olas;
    let ve;
    let bu;
    let sale;
    let signers;
    const initialMint = "1000000000000000000000000"; // 1000000
    const oneWeek = 7 * 86400;
    const oneYear = 365 * 86400;
    const numSteps = 4;
    const oneOLABalance = ethers.utils.parseEther("1");
    const twoOLABalance = ethers.utils.parseEther("2");
    const AddressZero = "0x" + "0".repeat(40);
    const overflowNum128 = "341" + "0".repeat(36);

    beforeEach(async function () {
        const OLAS = await ethers.getContractFactory("OLAS");
        olas = await OLAS.deploy();
        await olas.deployed();

        signers = await ethers.getSigners();
        await olas.mint(signers[0].address, initialMint);

        const VE = await ethers.getContractFactory("veOLAS");
        ve = await VE.deploy(olas.address, "name", "symbol");
        await ve.deployed();

        const BU = await ethers.getContractFactory("buOLAS");
        bu = await BU.deploy(olas.address, "name", "symbol");
        await bu.deployed();

        const SALE = await ethers.getContractFactory("Sale");
        sale = await SALE.deploy(olas.address, ve.address, bu.address);
        await sale.deployed();
    });

    context("Create balances for account", async function () {
        it("Changing owner", async function () {
            const owner = signers[0];
            const account = signers[1];

            // Trying to change owner from a non-owner account address
            await expect(
                sale.connect(account).changeOwner(account.address)
            ).to.be.revertedWith("OwnerOnly");

            // Trying to change owner for the zero address
            await expect(
                sale.connect(owner).changeOwner(AddressZero)
            ).to.be.revertedWith("ZeroAddress");

            // Changing the owner
            await sale.connect(owner).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                sale.connect(owner).changeOwner(owner.address)
            ).to.be.revertedWith("OwnerOnly");
        });

        it("Should fail when creating a claimable balance with wrong arguments", async function () {
            const account = signers[1].address;

            // Trying to call the createBalancesFor from a non owner
            await expect(
                sale.connect(signers[1]).createBalancesFor([], [], [], [], [], [])
            ).to.be.revertedWith("OwnerOnly");

            // **************************   veOLAS   *************************
            // Address for veOLAS is zero
            await expect(
                sale.createBalancesFor([AddressZero], [0], [0], [], [], [])
            ).to.be.revertedWith("ZeroAddress");

            // Amount for veOLAS is zero
            await expect(
                sale.createBalancesFor([account], [0], [0], [], [], [])
            ).to.be.revertedWith("ZeroValue");

            // Amount for veOLAS is above the limit
            await expect(
                sale.createBalancesFor([account], [overflowNum128], [oneYear], [], [], [])
            ).to.be.revertedWith("Overflow");

            // Time for veOLAS is less than one year
            await expect(
                sale.createBalancesFor([account], [oneOLABalance], [0], [], [], [])
            ).to.be.revertedWith("UnlockTimeIncorrect");

            // Time for veOLAS is bigger than the max time of 4 years
            await expect(
                sale.createBalancesFor([account], [oneOLABalance], [4 * oneYear + 1], [], [], [])
            ).to.be.revertedWith("MaxUnlockTimeReached");

            // Number array arguments for veOLAS is incorrect
            await expect(
                sale.createBalancesFor([account], [oneOLABalance, twoOLABalance], [oneYear], [], [], [])
            ).to.be.revertedWith("WrongArrayLength");

            await expect(
                sale.createBalancesFor([account], [oneOLABalance], [oneYear, 2 * oneYear], [], [], [])
            ).to.be.revertedWith("WrongArrayLength");

            // **************************   buOLAS   *************************
            // Address for buOLAS is zero
            await expect(
                sale.createBalancesFor([], [], [], [AddressZero], [0], [0])
            ).to.be.revertedWith("ZeroAddress");

            // Amount for buOLAS is zero
            await expect(
                sale.createBalancesFor([], [], [], [account], [0], [0])
            ).to.be.revertedWith("ZeroValue");

            // Amount for buOLAS is above the limit
            await expect(
                sale.createBalancesFor([], [], [], [account], [overflowNum128], [1])
            ).to.be.revertedWith("Overflow");

            // Number of time steps for buOLAS is zero
            await expect(
                sale.createBalancesFor([], [], [], [account], [oneOLABalance], [0])
            ).to.be.revertedWith("ZeroValue");

            // Number of time steps for buOLAS is more than the maximum number of steps
            await expect(
                sale.createBalancesFor([], [], [], [account], [oneOLABalance], [11])
            ).to.be.revertedWith("Overflow");

            // Number array arguments for buOLAS is incorrect
            await expect(
                sale.createBalancesFor([], [], [], [account], [oneOLABalance, twoOLABalance], [1])
            ).to.be.revertedWith("WrongArrayLength");

            await expect(
                sale.createBalancesFor([], [], [], [account], [oneOLABalance], [1, 2])
            ).to.be.revertedWith("WrongArrayLength");
        });

        it("Create balances for", async function () {
            const account = signers[1].address;

            // Check the account possibility to claim
            let balances = await sale.claimableBalances(account);
            expect(balances.veBalance).to.equal(0);
            expect(balances.buBalance).to.equal(0);

            // Trying to create balances without any Sale balance
            await expect(
                sale.createBalancesFor([account], [oneOLABalance], [oneYear], [account], [oneOLABalance], [numSteps])
            ).to.be.revertedWith("InsufficientAllowance");

            // Mint OLAS for the Sale contract
            await olas.mint(sale.address, twoOLABalance);

            // Create balances for veOLAS and buOLAS and check statuses
            await sale.createBalancesFor([account], [oneOLABalance], [oneYear], [account], [oneOLABalance], [numSteps]);

            balances = await sale.claimableBalances(account);
            expect(balances.veBalance).to.equal(oneOLABalance);
            expect(balances.buBalance).to.equal(oneOLABalance);

            // Try to create additional balance after the existent one
            await expect(
                sale.createBalancesFor([account], [oneOLABalance], [oneYear], [], [], [])
            ).to.be.revertedWith("NonZeroValue");

            await expect(
                sale.createBalancesFor([], [], [], [account], [oneOLABalance], [numSteps])
            ).to.be.revertedWith("NonZeroValue");

            // Trying to create more balances without sufficient amount
            await expect(
                sale.createBalancesFor([signers[2].address], [oneOLABalance], [oneYear], [], [], [])
            ).to.be.revertedWith("InsufficientAllowance");
        });
    });

    context("Claim", async function () {
        it("Claim for one account with veOLAS", async function () {
            const account = signers[1];

            // Mint OLAS for the Sale contract
            await olas.mint(sale.address, oneOLABalance);

            // Create balance for account in veOLAS
            await sale.createBalancesFor([account.address], [oneOLABalance], [oneYear], [], [], []);

            // Claim the balance for veOLAS
            await sale.connect(account).claim();
            // Record the current block (needed for checking the unlock time)
            const block = await ethers.provider.getBlock("latest");
            // Check the claimable balance after the claim
            const claimableBalances = await sale.claimableBalances(account.address);
            expect(claimableBalances.veBalance).to.equal(0);

            // Trying to claim more
            await expect(
                sale.connect(account).claim()
            ).to.be.revertedWith("ZeroValue");

            // Check the status of the lock in veOLAS
            // Check the balance
            const balance = await ve.balanceOf(account.address);
            expect(balance).to.equal(oneOLABalance);
            // Check the lock time
            const lockEnd = await ve.lockedEnd(account.address);
            expect(Math.floor((block.timestamp + oneYear) / oneWeek) * oneWeek).to.equal(lockEnd);
        });

        it("Claim for one account with buOLAS", async function () {
            const account = signers[1];

            // Mint OLAS for the Sale contract
            await olas.mint(sale.address, oneOLABalance);

            // Create balance for account in buOLAS
            await sale.createBalancesFor([], [], [], [account.address], [oneOLABalance], [numSteps]);

            // Claim the balance for buOLAS
            await sale.connect(account).claim();
            // Record the current block (needed for checking the unlock time)
            const block = await ethers.provider.getBlock("latest");
            // Check the claimable balance after the claim
            const claimableBalances = await sale.claimableBalances(account.address);
            expect(claimableBalances.buBalance).to.equal(0);

            // Trying to claim more
            await expect(
                sale.connect(account).claim()
            ).to.be.revertedWith("ZeroValue");

            // Check the status of the lock in buOLAS
            // Check the balance
            const balance = await bu.balanceOf(account.address);
            expect(balance).to.equal(oneOLABalance);
            // Check the lock time
            const lockEnd = await bu.lockedEnd(account.address);
            expect(block.timestamp + oneYear * numSteps).to.equal(lockEnd);
        });

        it("Claim for one account with both veOLAS and buOLAS", async function () {
            const account = signers[1];

            // Mint OLAS for the Sale contract
            await olas.mint(sale.address, twoOLABalance);

            // Create balance for account in veOLAS and buOLAS
            await sale.createBalancesFor([account.address], [oneOLABalance], [oneYear],
                [account.address], [oneOLABalance], [numSteps]);

            // Claim the balance for both veOLAS and buOLAS
            await sale.connect(account).claim();
            // Record the current block (needed for checking the unlock time)
            const block = await ethers.provider.getBlock("latest");

            // Check the claimable balance after the claim for both tokens
            const claimableBalances = await sale.claimableBalances(account.address);
            expect(claimableBalances.veBalance).to.equal(0);
            expect(claimableBalances.buBalance).to.equal(0);

            // Check the status of the locks
            // Check the balance
            let balance = await ve.balanceOf(account.address);
            expect(balance).to.equal(oneOLABalance);
            balance = await bu.balanceOf(account.address);
            expect(balance).to.equal(oneOLABalance);
            // Check the lock time
            let lockEnd = await ve.lockedEnd(account.address);
            expect(Math.floor((block.timestamp + oneYear) / oneWeek) * oneWeek).to.equal(lockEnd);
            lockEnd = await bu.lockedEnd(account.address);
            expect(block.timestamp + oneYear * numSteps).to.equal(lockEnd);
        });

        it("Claim for two accounts with veOLAS", async function () {
            const accounts = [signers[1], signers[2]];

            // Mint OLAS for the Sale contract
            await olas.mint(sale.address, twoOLABalance);

            // Create balance for account in veOLAS
            await sale.createBalancesFor([accounts[0].address, accounts[1].address], [oneOLABalance, oneOLABalance],
                [oneYear, oneYear], [], [], []);

            // Claim the balance for veOLAS
            await sale.connect(accounts[0]).claim();
            await sale.connect(accounts[1]).claim();
            // Record the current block (needed for checking the unlock time)
            const block = await ethers.provider.getBlock("latest");

            // Check the claimable balance after the claim for both tokens
            let claimableBalances = await sale.claimableBalances(accounts[0].address);
            expect(claimableBalances.veBalance).to.equal(0);
            claimableBalances = await sale.claimableBalances(accounts[1].address);
            expect(claimableBalances.veBalance).to.equal(0);

            // Check the status of the locks
            // Check the balance
            let balance = await ve.balanceOf(accounts[0].address);
            expect(balance).to.equal(oneOLABalance);
            balance = await ve.balanceOf(accounts[1].address);
            expect(balance).to.equal(oneOLABalance);
            // Check the lock time
            let lockEnd = await ve.lockedEnd(accounts[0].address);
            expect(Math.floor((block.timestamp + oneYear) / oneWeek) * oneWeek).to.equal(lockEnd);
            lockEnd = await ve.lockedEnd(accounts[1].address);
            expect(Math.floor((block.timestamp + oneYear) / oneWeek) * oneWeek).to.equal(lockEnd);
        });
    });
});
