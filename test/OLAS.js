/*global describe, context, beforeEach, it*/
const { ethers } = require("hardhat");
const { expect } = require("chai");
const { signERC2612Permit } = require("eth-permit");

describe("OLAS", function () {
    let deployer;
    let treasury;
    let bob;
    let alice;
    let ola;
    let olaFactory;
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
        olaFactory = await ethers.getContractFactory("OLAS");
        // Treasury address is deployer by default
        ola = await olaFactory.deploy(initSupply);
        // Changing the treasury address
        await ola.connect(deployer).changeMinter(treasury.address);
    });

    context("Initialization", async function () {
        it("correctly constructs an ERC20", async () => {
            expect(await ola.name()).to.equal("Autonolas");
            expect(await ola.symbol()).to.equal("OLAS");
            expect(await ola.decimals()).to.equal(18);
        });

        it("Change owner", async function () {
            const owner = deployer;
            const account = bob;

            // Trying to change owner from a non-owner account address
            await expect(
                ola.connect(account).changeOwner(account.address)
            ).to.be.revertedWith("ManagerOnly");

            // Trying to change owner for the zero address
            await expect(
                ola.connect(owner).changeOwner(AddressZero)
            ).to.be.revertedWith("ZeroAddress");

            // Changing the owner
            await ola.connect(owner).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                ola.connect(owner).changeOwner(owner.address)
            ).to.be.revertedWith("ManagerOnly");
        });

        it("Change minter", async function () {
            const owner = deployer;
            const account = bob;

            // Trying to change minter from a non-owner account address
            await expect(
                ola.connect(account).changeMinter(account.address)
            ).to.be.revertedWith("ManagerOnly");

            // Trying to change minter for the zero address
            await expect(
                ola.connect(owner).changeMinter(AddressZero)
            ).to.be.revertedWith("ZeroAddress");

            // Changing the minter
            await ola.connect(owner).changeMinter(account.address);
        });
    });

    context("Mint", () => {
        it("Mint must be done by manager", async function () {
            await expect(
                ola.connect(bob).mint(bob.address, amount)
            ).to.be.revertedWith("ManagerOnly");
        });

        it("Increases total supply", async function () {
            const supplyBefore = await ola.totalSupply();
            await ola.connect(treasury).mint(bob.address, amount);
            expect(supplyBefore.add(amount)).to.equal(await ola.totalSupply());
        });
    });

    context("Burn", async function () {
        beforeEach(async function () {
            await ola.connect(treasury).mint(bob.address, amount);
        });

        it("Reduces the total supply", async function () {
            const supplyBefore = await ola.totalSupply();
            await ola.connect(bob).burn(10);
            expect(supplyBefore.sub(10)).to.equal(await ola.totalSupply());
        });
    });

    context("Transfer", async function () {
        it("Transfer from self", async function () {
            await ola.connect(treasury).mint(bob.address, amount);
            await ola.connect(bob).transfer(alice.address, amount);
            expect(await ola.balanceOf(alice.address)).to.equal(amount);
        });

        it("Transfer from via approve", async function () {
            await ola.connect(treasury).mint(bob.address, amount);
            await ola.connect(bob).approve(alice.address, amount);
            await ola.connect(alice).transferFrom(bob.address, alice.address, amount);
            expect(await ola.balanceOf(alice.address)).to.equal(amount);
        });

        it("Transfer from via permit", async function () {
            await ola.connect(treasury).mint(bob.address, amount);
            const result = await signERC2612Permit(bob, ola.address, bob.address, alice.address, amount);
            await ola.permit(bob.address, alice.address, amount, result.deadline,
                result.v, result.r, result.s);
            await ola.connect(alice).transferFrom(bob.address, alice.address, amount);
            expect(await ola.balanceOf(alice.address)).to.equal(amount);
        });

        it("Transfer from with increase allowance", async function () {
            await ola.connect(treasury).mint(bob.address, amount);
            await ola.connect(bob).approve(alice.address, amount - 50);
            // Trying to do transferFrom with insufficient allowance
            await expect(
                ola.connect(alice).transferFrom(bob.address, alice.address, amount)
            ).to.be.revertedWith("panic code 0x11");
            // Increasing allowance
            await ola.connect(bob).increaseAllowance(alice.address, amount - 50);
            await ola.connect(alice).transferFrom(bob.address, alice.address, amount);
            expect(await ola.balanceOf(alice.address)).to.equal(amount);
        });

        it("Transfer from with maximum allowance", async function () {
            await ola.connect(treasury).mint(bob.address, amount);
            await ola.connect(bob).approve(alice.address, maxNum256);
            // Decreasing allowance will not change it and thus transferFrom will go through
            await ola.connect(bob).decreaseAllowance(alice.address, maxNum256);
            await ola.connect(alice).transferFrom(bob.address, alice.address, amount);
            expect(await ola.balanceOf(alice.address)).to.equal(amount);
        });

        it("Transfer from with decrease allowance", async function () {
            await ola.connect(treasury).mint(bob.address, amount);
            await ola.connect(bob).approve(alice.address, amount);
            // Decreasing allowance
            await ola.connect(bob).decreaseAllowance(alice.address, amount - 50);
            // Trying to do transferFrom for a full amount with insufficient allowance
            await expect(
                ola.connect(alice).transferFrom(bob.address, alice.address, amount)
            ).to.be.revertedWith("panic code 0x11");
            await ola.connect(alice).transferFrom(bob.address, alice.address, amount - 50);
            expect(await ola.balanceOf(alice.address)).to.equal(amount - 50);
        });
    });

    context("Mint schedule", async function () {
        it("Should fail when mint more than a supplyCap within the first ten years", async () => {
            const supplyCap = await ola.tenYearSupplyCap();
            let amount = supplyCap;
            // Mint more than the supply cap is not possible
            let totalSupply = await ola.totalSupply();
            await ola.connect(treasury).mint(deployer.address, amount);
            expect(await ola.totalSupply()).to.equal(totalSupply);

            // Move 9 years in time
            const blockNumber = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNumber);
            await ethers.provider.send("evm_mine", [block.timestamp + nineYears + 1000]);

            // Mint up to the supply cap
            amount = "5" + "0".repeat(26);
            await ola.connect(treasury).mint(deployer.address, amount);

            // Check the total supply that must be equal to the supply cap
            totalSupply = await ola.totalSupply();
            expect(totalSupply).to.equal(supplyCap);
        });

        it("Mint and burn after ten years", async function () {
            const supplyCap = await ola.tenYearSupplyCap();
            let amount = supplyCap;
            // Mint more than the supply cap is not possible
            let totalSupply = await ola.totalSupply();
            await ola.connect(treasury).mint(deployer.address, amount);
            expect(await ola.totalSupply()).to.equal(totalSupply);           

            // Move 10 years in time
            let blockNumber = await ethers.provider.getBlockNumber();
            let block = await ethers.provider.getBlock(blockNumber);
            await ethers.provider.send("evm_mine", [block.timestamp + tenYears + 1000]);

            // Calculate expected supply cap starting from the max for 10 years, i.e. 1 billion
            const supplyCapFraction = await ola.maxMintCapFraction();
            let expectedSupplyCap = supplyCap + (supplyCap * supplyCapFraction) / 100;
            //console.log(expectedSupplyCap);

            // Mint up to the supply cap that is up to the renewed supply cap after ten years
            // New total supply is 1 * 1.02 = 1.02 billion. We can safely mint 9 million
            amount = "519" + "0".repeat(24);
            await ola.connect(treasury).mint(deployer.address, amount);
            totalSupply = await ola.totalSupply();
            expect(Number(totalSupply)).to.be.lessThan(Number(expectedSupplyCap));
            //console.log("updated total supply", totalSupply);

            // Mint more than a new total supply must not go through (will not change the supply)
            amount = "2" + "0".repeat(24);
            await ola.connect(treasury).mint(deployer.address, amount);
            expect(await ola.totalSupply()).to.equal(totalSupply);

            // Move 3 more years in time, in addition to what we have already surpassed 10 years
            // So it will be the beginning of a year 4 after first 10 years
            blockNumber = await ethers.provider.getBlockNumber();
            block = await ethers.provider.getBlock(blockNumber);
            await ethers.provider.send("evm_mine", [block.timestamp + threeYears + 1000]);
            // Calculate max supply cap after 4 years in total
            expectedSupplyCap = supplyCap;
            for (let i = 0; i < 4; ++i) {
                expectedSupplyCap += (expectedSupplyCap * supplyCapFraction) / 100;
            }

            // The max supply now is 1,082,432,160 * E18
            // Mint 60 million more
            amount = "6" + "0".repeat(25);
            await ola.connect(treasury).mint(deployer.address, amount);

            // Mint 5 more million must not change the total supply due to the overflow
            totalSupply = await ola.totalSupply();
            amount = "5" + "0".repeat(24);
            await ola.connect(treasury).mint(deployer.address, amount);
            expect(await ola.totalSupply()).to.equal(totalSupply);

            // Burn the amount such that the total supply drops below 1 billion
            amount = "1" + "0".repeat(26);
            // Total supply minus the amount to be burned
            const expectedTotalSupply = new ethers.BigNumber.from(await ola.totalSupply()).sub(amount);
            await ola.connect(deployer).burn(amount);
            // Check the final total amount
            expect(await ola.totalSupply()).to.equal(expectedTotalSupply);
        });
    });
});