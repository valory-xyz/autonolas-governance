/*global describe, context, beforeEach, it*/
const { ethers } = require("hardhat");
const { expect } = require("chai");
const { signERC2612Permit } = require("eth-permit");

describe("OLAS", () => {
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

    beforeEach(async () => {
        [deployer, treasury, bob, alice] = await ethers.getSigners();
        olaFactory = await ethers.getContractFactory("OLAS");
        // Treasury address is deployer by default
        ola = await olaFactory.deploy(initSupply);
        // Changing the treasury address
        await ola.connect(deployer).changeMinter(treasury.address);
    });

    context("Initialization", () => {
        it("correctly constructs an ERC20", async () => {
            expect(await ola.name()).to.equal("Autonolas");
            expect(await ola.symbol()).to.equal("OLAS");
            expect(await ola.decimals()).to.equal(18);
        });
    });

    context("Mint", () => {
        it("Must be done by treasury", async () => {
            await expect(ola.connect(bob).mint(bob.address, 100)).to.be.revertedWith(
                "ManagerOnly"
            );
        });

        it("Increases total supply", async () => {
            const supplyBefore = await ola.totalSupply();
            await ola.connect(treasury).mint(bob.address, 100);
            expect(supplyBefore.add(100)).to.equal(await ola.totalSupply());
        });
    });

    context("Burn", () => {
        beforeEach(async () => {
            await ola.connect(treasury).mint(bob.address, 100);
        });

        it("Reduces the total supply", async () => {
            const supplyBefore = await ola.totalSupply();
            await ola.connect(bob).burn(10);
            expect(supplyBefore.sub(10)).to.equal(await ola.totalSupply());
        });
    });

    context("Transfer", () => {
        it("Transfer from self", async () => {
            await ola.connect(treasury).mint(bob.address, 100);
            await ola.connect(bob).transfer(alice.address, amount);
            expect(await ola.balanceOf(alice.address)).to.equal(amount);
        });

        it("Transfer from via approve", async () => {
            await ola.connect(treasury).mint(bob.address, 100);
            await ola.connect(bob).approve(alice.address, amount);
            await ola.connect(alice).transferFrom(bob.address, alice.address, amount);
            expect(await ola.balanceOf(alice.address)).to.equal(amount);
        });

        it("Transfer from via permit", async () => {
            await ola.connect(treasury).mint(bob.address, 100);
            const result = await signERC2612Permit(bob, ola.address, bob.address, alice.address, amount);
            await ola.permit(bob.address, alice.address, amount, result.deadline,
                result.v, result.r, result.s);
            await ola.connect(alice).transferFrom(bob.address, alice.address, amount);
            expect(await ola.balanceOf(alice.address)).to.equal(amount);
        });
    });

    context("Mint schedule", () => {
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

        it("Mint and burn after ten years", async () => {
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
