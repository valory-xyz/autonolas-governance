/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("buOLAS", function () {
    let olas;
    let bu;
    let signers;
    const initialMint = "1000000000000000000000000"; // 1000000
    const oneYear = 365 * 86400;
    const quarterOLABalance = ethers.utils.parseEther("0.25");
    const oneOLABalance = ethers.utils.parseEther("1");
    const AddressZero = "0x" + "0".repeat(40);
    const overflowNum96 = "8" + "0".repeat(28);

    beforeEach(async function () {
        const OLAS = await ethers.getContractFactory("OLAS");
        olas = await OLAS.deploy(0);
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
            ).to.be.revertedWith("OwnerOnly");

            // Trying to change owner for the zero address
            await expect(
                bu.connect(owner).changeOwner(AddressZero)
            ).to.be.revertedWith("ZeroAddress");

            // Changing the owner
            await bu.connect(owner).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                bu.connect(owner).changeOwner(owner.address)
            ).to.be.revertedWith("OwnerOnly");
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
            await olas.approve(bu.address, oneOLABalance);

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
                bu.createLockFor(account, overflowNum96, 1)
            ).to.be.revertedWith("Overflow");

            await expect(
                bu.createLockFor(account, oneOLABalance, 11)
            ).to.be.revertedWith("Overflow");
        });

        it("Create lock for", async function () {
            const owner = signers[0];
            const account = signers[1];

            // Approve owner for 1 OLAS by buOLAS
            await olas.connect(owner).approve(bu.address, oneOLABalance);

            // Define 4 years for the lock duration
            const numSteps = 4;

            // Balance should be zero before the lock
            expect(await bu.balanceOf(account.address)).to.equal(0);
            // Create lock for the account address, which is called by the owner (approved for buOLAS)
            await bu.connect(owner).createLockFor(account.address, oneOLABalance, numSteps);

            // Lock end is rounded by 1 week, as implemented by design
            const lockEnd = await bu.lockedEnd(account.address);
            const block = await ethers.provider.getBlock("latest");
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

            // Try to withdraw without any locks
            await bu.connect(account).withdraw()
            expect(await olas.balanceOf(account.address)).to.equal(0);

            // Approve owner for 1 OLAS by buOLAS that will be locked for account
            await olas.connect(owner).approve(bu.address, oneOLABalance);

            // Define 4 years for the lock duration
            const numSteps = 4;
            await bu.connect(owner).createLockFor(account.address, oneOLABalance, numSteps);

            // Try to withdraw early
            await expect(bu.connect(account).withdraw()).to.be.revertedWith("LockNotExpired");
            // Move one year in time
            ethers.provider.send("evm_increaseTime", [oneYear + 100]);
            ethers.provider.send("evm_mine");
            // Withdraw must be equal to 1/4 of the total amount
            expect(await olas.balanceOf(account.address)).to.equal(0);
            await bu.connect(account).withdraw();
            expect(await olas.balanceOf(account.address)).to.equal(quarterOLABalance);

            // Try to withdraw more now
            await expect(
                bu.connect(account).withdraw()
            ).to.be.revertedWith("LockNotExpired");

            // Move time after the lock duration
            ethers.provider.send("evm_increaseTime", [3 * oneYear + 100]);
            ethers.provider.send("evm_mine");

            // Now withdraw must get us the rest
            await bu.connect(account).withdraw();
            expect(await olas.balanceOf(account.address)).to.equal(oneOLABalance);
        });

        it("Withdraw with not divisible remainder", async function () {
            const owner = signers[0];
            const account = signers[1];

            // Approve owner for 1 OLAS by buOLAS that will be locked for account
            await olas.connect(owner).approve(bu.address, oneOLABalance);

            // Define 3 years for the lock duration
            const numSteps = 3;
            await bu.connect(owner).createLockFor(account.address, oneOLABalance, numSteps);

            // Move one year in time
            ethers.provider.send("evm_increaseTime", [oneYear + 100]);
            ethers.provider.send("evm_mine");
            // Withdraw must be equal to rounded 1/3 of the total amount
            const thirdOLABalance = new ethers.BigNumber.from(oneOLABalance).div(numSteps);
            await bu.connect(account).withdraw();
            const recoveredFullBalance = thirdOLABalance.mul(numSteps);
            expect(await olas.balanceOf(account.address)).to.equal(thirdOLABalance);
            // This proves that we can potentially lose only 1e(-18) tokens if we call revoke on non divisible remainder
            expect(recoveredFullBalance.add(1)).to.equal(oneOLABalance);

            // Move time after the lock duration
            ethers.provider.send("evm_increaseTime", [2 * oneYear + 100]);
            ethers.provider.send("evm_mine");

            // At the end we withdraw the remainder that gets the rest with 1e(-18) tokens that were not partitioned
            await bu.connect(account).withdraw();
            expect(await olas.balanceOf(account.address)).to.equal(oneOLABalance);
        });

        it("Withdraw with revoke", async function () {
            const owner = signers[0];
            const account = signers[1];

            // Approve owner for 1 OLAS by buOLAS that will be locked for account
            await olas.connect(owner).approve(bu.address, oneOLABalance);

            // Define 4 years for the lock duration
            const numSteps = 4;
            await bu.connect(owner).createLockFor(account.address, oneOLABalance, numSteps);
            // Check the balanceOf that must be equal to the full locked amount
            let balance = await bu.balanceOf(account.address);
            expect(balance).to.equal(oneOLABalance);

            // Try to revoke not by the owner
            await expect(
                bu.connect(account).revoke([account.address])
            ).to.be.revertedWith("OwnerOnly");

            // Move one year in time
            ethers.provider.send("evm_increaseTime", [oneYear + 100]);
            ethers.provider.send("evm_mine");
            // Revoke at this point of time
            await bu.connect(owner).revoke([account.address]);
            // The buOLAS balanceOf must be equal to the releasable amount after the revoke
            balance = await bu.balanceOf(account.address);
            expect(balance).to.equal(quarterOLABalance);

            // Move time after the full lock duration
            ethers.provider.send("evm_increaseTime", [3 * oneYear + 100]);
            ethers.provider.send("evm_mine");

            // The releasable amount must still be the 1/4 amount, since the rest was revoked
            let amount = await bu.releasableAmount(account.address);
            expect(amount).to.equal(quarterOLABalance);

            // Withdraw must be equal to 1/4 of the total amount since another 3/4 has been revoked
            expect(await olas.balanceOf(account.address)).to.equal(0);
            // Before the withdraw the total supply is still equal to the full balance
            let supply = await bu.totalSupply();
            expect(supply).to.equal(oneOLABalance);
            // Withdraw what we can for the account
            await bu.connect(account).withdraw();
            expect(await olas.balanceOf(account.address)).to.equal(quarterOLABalance);
            // Now the balance is zero, since the rest of 3/4 tokens were burned
            supply = await bu.totalSupply();
            expect(supply).to.equal(0);

            // Now there is no releasable amount left
            amount = await bu.releasableAmount(account.address);
            expect(amount).to.equal(0);
        });

        it("Withdraw with revoke after the first withdraw", async function () {
            const owner = signers[0];
            const account = signers[1];

            // Approve owner for 1 OLAS by buOLAS that will be locked for account
            await olas.connect(owner).approve(bu.address, oneOLABalance);

            // Define 3 years for the lock duration
            const numSteps = 3;
            await bu.connect(owner).createLockFor(account.address, oneOLABalance, numSteps);

            // Move one year in time
            ethers.provider.send("evm_increaseTime", [oneYear + 100]);
            ethers.provider.send("evm_mine");
            // Withdraw after the first year
            await bu.connect(account).withdraw();

            // Move one more year in time
            ethers.provider.send("evm_increaseTime", [oneYear + 100]);
            ethers.provider.send("evm_mine");
            // Revoke at this point of time
            await bu.connect(owner).revoke([account.address]);
            // The buOLAS balanceOf must be equal to the releasable amount after the revoke, which is 1/3
            const thirdOLABalance = new ethers.BigNumber.from(oneOLABalance).div(numSteps);
            const balance = await bu.balanceOf(account.address);
            expect(balance).to.equal(thirdOLABalance);

            // The releasable amount must be the 1/3 amount, since the rest 1/3 was revoked
            let amount = await bu.releasableAmount(account.address);
            expect(amount).to.equal(thirdOLABalance);

            const twoThirdsOLABalance = thirdOLABalance.mul(2);
            // Before the withdraw the total supply is equal to 2/3 of the full balance, since 1/3 was already withdrawn
            let supply = await bu.totalSupply();
            expect(supply).to.equal(twoThirdsOLABalance.add(1));
            // Withdraw what we can for the account, after which the balance is 2/3 of the initial balance
            await bu.connect(account).withdraw();
            expect(await olas.balanceOf(account.address)).to.equal(twoThirdsOLABalance);
            // Now the balance is zero, since the rest of 1/3 tokens were burned
            supply = await bu.totalSupply();
            expect(supply).to.equal(0);

            // Now there is no releasable amount left
            amount = await bu.releasableAmount(account.address);
            expect(amount).to.equal(0);
        });

        it("Withdraw with revoke after the full lock period", async function () {
            const owner = signers[0];
            const account = signers[1];

            // Approve owner for 1 OLAS by buOLAS that will be locked for account
            await olas.connect(owner).approve(bu.address, oneOLABalance);

            // Define 3 years for the lock duration
            const numSteps = 3;
            await bu.connect(owner).createLockFor(account.address, oneOLABalance, numSteps);

            // Move three years in time
            ethers.provider.send("evm_increaseTime", [3 * oneYear + 100]);
            ethers.provider.send("evm_mine");
            // Revoke at this point of time
            await bu.connect(owner).revoke([account.address]);

            // The releasable amount must be the full locked amount, since the revoke took place after the lock time
            let amount = await bu.releasableAmount(account.address);
            expect(amount).to.equal(oneOLABalance);
            // Same about buOLAS balance
            const balance = await bu.balanceOf(account.address);
            expect(balance).to.equal(oneOLABalance);
            // Withdraw must return all the initially locked amount
            await bu.connect(account).withdraw();
            // The buOLAS balanceOf must be equal to the full initial amount after revoke
            expect(await olas.balanceOf(account.address)).to.equal(oneOLABalance);

            // The supply must also be zero at this point of time
            const supply = await bu.totalSupply();
            expect(supply).to.equal(0);

            // There is also no releasable amount left
            amount = await bu.releasableAmount(account.address);
            expect(amount).to.equal(0);
        });
    });

    context("IERC20 functions", async function () {
        it("Check all the related functions", async function () {
            const deployer = signers[0].address;
            const user = signers[1].address;
            // Try to call transfer-related functions for buOLAS
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
