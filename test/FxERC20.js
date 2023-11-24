/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe.("FxERC20", function () {
    let fxERC20RootTunnel;
    let fxERC20ChildTunnel;
    let childToken;
    let rootToken;
    let signers;
    let deployer;
    const AddressZero = ethers.constants.AddressZero;
    const stateId = 0;
    const initMint = "1" + "0".repeat(20);
    const amount = 1000;

    beforeEach(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];

        // Child token on L2
        const ChildMockERC20 = await ethers.getContractFactory("ChildMockERC20");
        childToken = await ChildMockERC20.deploy();
        await childToken.deployed();

        // Root token is a bridged ERC20 token
        const BridgedToken = await ethers.getContractFactory("BridgedERC20");
        rootToken = await BridgedToken.deploy("Bridged token", "BERC20");
        await rootToken.deployed();

        // ERC20 tunnels
        const FxRootMock = await ethers.getContractFactory("FxRootMock");
        const fxRootMock = await FxRootMock.deploy();
        await fxRootMock.deployed();

        const FxERC20RootTunnel = await ethers.getContractFactory("FxERC20RootTunnel");
        fxERC20RootTunnel = await FxERC20RootTunnel.deploy(deployer.address, fxRootMock.address, childToken.address,
            rootToken.address);
        await fxERC20RootTunnel.deployed();

        // Set the FxERC20RootTunnel address such that the FxRootMock routes the call from the FxERC20RootTunnel
        // directly to the FxERC20ChildTunnel to simulate the cross-chain message sending
        await fxRootMock.setRootTunnel(fxERC20RootTunnel.address);

        const FxERC20ChildTunnel = await ethers.getContractFactory("FxERC20ChildTunnel");
        // FxRootMock is the mock for FxChild contract address in order to re-route message sending for testing purposes
        fxERC20ChildTunnel = await FxERC20ChildTunnel.deploy(fxRootMock.address, childToken.address, rootToken.address);
        await fxERC20ChildTunnel.deployed();

        // Set child and root tunnels accordingly
        await fxERC20RootTunnel.setFxChildTunnel(fxERC20ChildTunnel.address);
        await fxERC20ChildTunnel.setFxRootTunnel(fxERC20RootTunnel.address);

        // Mint tokens
        await childToken.mint(deployer.address, initMint);
    });

    context("Initialization", async function () {
        it("Deploying with zero addresses", async function () {
            const FxERC20RootTunnel = await ethers.getContractFactory("FxERC20RootTunnel");
            await expect(
                FxERC20RootTunnel.deploy(AddressZero, AddressZero, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(fxERC20RootTunnel, "ZeroAddress");

            await expect(
                FxERC20RootTunnel.deploy(signers[1].address, AddressZero, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(fxERC20RootTunnel, "ZeroAddress");

            await expect(
                FxERC20RootTunnel.deploy(signers[1].address, signers[1].address, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(fxERC20RootTunnel, "ZeroAddress");

            await expect(
                FxERC20RootTunnel.deploy(signers[1].address, signers[1].address, signers[1].address, AddressZero)
            ).to.be.revertedWithCustomError(fxERC20RootTunnel, "ZeroAddress");

            const FxERC20ChildTunnel = await ethers.getContractFactory("FxERC20ChildTunnel");
            await expect(
                FxERC20ChildTunnel.deploy(AddressZero, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(fxERC20ChildTunnel, "ZeroAddress");

            await expect(
                FxERC20ChildTunnel.deploy(signers[1].address, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(fxERC20ChildTunnel, "ZeroAddress");

            await expect(
                FxERC20ChildTunnel.deploy(signers[1].address, signers[1].address, AddressZero)
            ).to.be.revertedWithCustomError(fxERC20ChildTunnel, "ZeroAddress");
        });
    });

    context("Deposit and withdraw ERC20 tokens", async function () {
        it("Should fail when trying to call from incorrect contract addresses", async function () {
            // signers[1].address as a sender is incorrect, must be deployer.address (aka FxChild in the setup)
            await expect(
                fxERC20ChildTunnel.connect(signers[1]).processMessageFromRoot(stateId, deployer.address, "0x")
            ).to.be.revertedWith("FxBaseChildTunnel: INVALID_SENDER");

            // deployer is the FxChild for testing purposes
            const FxERC20ChildTunnel = await ethers.getContractFactory("FxERC20ChildTunnel");
            const testChildTunnel = await FxERC20ChildTunnel.deploy(deployer.address, childToken.address, rootToken.address);
            await testChildTunnel.deployed();

            // deployer.address as an FxERC20RootTunnel is incorrect
            await expect(
                testChildTunnel.connect(deployer).processMessageFromRoot(stateId, deployer.address, "0x")
            ).to.be.revertedWith("FxBaseChildTunnel: INVALID_SENDER_FROM_ROOT");
        });

        it("Deposit tokens", async function () {
            // Approve tokens
            await childToken.approve(fxERC20ChildTunnel.address, amount);

            // Send tokens to L1
            await fxERC20ChildTunnel.connect(deployer).deposit(amount);

            // Tokens must be locked on the FxERC20ChildTunnel contract address
            const balance = await childToken.balanceOf(fxERC20ChildTunnel.address);
            expect(balance).to.equal(amount);

            // On L1 fxERC20RootTunnel will be passed a proof validation data that the tx has happened on L2
            await rootToken.mint(deployer.address, amount);
        });

        it("Deposit tokens to a different address", async function () {
            const account = signers[1].address;

            // Approve tokens
            await childToken.approve(fxERC20ChildTunnel.address, amount);

            // Send tokens to L1
            await fxERC20ChildTunnel.connect(deployer).depositTo(account, amount);

            // Tokens must be locked on the FxERC20ChildTunnel contract address
            const balance = await childToken.balanceOf(fxERC20ChildTunnel.address);
            expect(balance).to.equal(amount);

            // On L1 fxERC20RootTunnel will be passed a proof validation data that the tx has happened on L2
            await rootToken.mint(account, amount);
        });

        it("Withdraw tokens", async function () {
            // Approve tokens
            await childToken.connect(deployer).approve(fxERC20ChildTunnel.address, amount);

            // Send tokens to L1
            await fxERC20ChildTunnel.connect(deployer).deposit(amount);

            // Tokens must be locked on the FxERC20ChildTunnel contract address
            let balance = await childToken.balanceOf(fxERC20ChildTunnel.address);
            expect(balance).to.equal(amount);

            // On L1 fxERC20RootTunnel will be passed a proof validation data that the tx has happened on L2
            await rootToken.mint(deployer.address, amount);

            // Withdraw tokens
            await rootToken.connect(deployer).approve(fxERC20RootTunnel.address, amount);

            // Root token must be owned by the FxERC20RootTunnel contract
            await rootToken.changeOwner(fxERC20RootTunnel.address);

            const balanceBefore = await childToken.balanceOf(deployer.address);

            // Burn tokens on L1 and send message to L2 to retrieve them there
            await fxERC20RootTunnel.withdraw(amount);

            // Check that bridged tokens were burned
            balance = await rootToken.balanceOf(deployer.address);
            expect(balance).to.equal(0);

            // There must be no balance left locked on the FxERC20ChildTunnel contract
            balance = await childToken.balanceOf(fxERC20ChildTunnel.address);
            expect(balance).to.equal(0);

            // The receiver balance must increase for the amount sent
            const balanceAfter = await childToken.balanceOf(deployer.address);
            const balanceDiff = Number(balanceAfter.sub(balanceBefore));
            expect(balanceDiff).to.equal(amount);
        });

        it("Withdraw tokens to a different address", async function () {
            const account = signers[1];

            // Approve tokens
            await childToken.connect(deployer).approve(fxERC20ChildTunnel.address, amount);

            // Send tokens to L1
            await fxERC20ChildTunnel.connect(deployer).depositTo(account.address, amount);

            // Tokens must be locked on the FxERC20ChildTunnel contract address
            let balance = await childToken.balanceOf(fxERC20ChildTunnel.address);
            expect(balance).to.equal(amount);

            // On L1 fxERC20RootTunnel will be passed a proof validation data that the tx has happened on L2
            await rootToken.mint(account.address, amount);

            // Withdraw tokens
            await rootToken.connect(account).approve(fxERC20RootTunnel.address, amount);

            // Root token must be owned by the FxERC20RootTunnel contract
            await rootToken.changeOwner(fxERC20RootTunnel.address);

            const balanceBefore = await childToken.balanceOf(deployer.address);

            // Burn tokens on L1 and send message to L2 to retrieve them there
            await fxERC20RootTunnel.connect(account).withdrawTo(deployer.address, amount);

            // Check that bridged tokens were burned
            balance = await rootToken.balanceOf(account.address);
            expect(balance).to.equal(0);

            // There must be no balance left locked on the FxERC20ChildTunnel contract
            balance = await childToken.balanceOf(fxERC20ChildTunnel.address);
            expect(balance).to.equal(0);

            // The receiver balance must increase for the amount sent
            const balanceAfter = await childToken.balanceOf(deployer.address);
            const balanceDiff = Number(balanceAfter.sub(balanceBefore));
            expect(balanceDiff).to.equal(amount);
        });
    });
});
