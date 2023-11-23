/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("FxERC20", function () {
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
        const FxERC20RootTunnel = await ethers.getContractFactory("FxERC20RootTunnel");
        fxERC20RootTunnel = await FxERC20RootTunnel.deploy(deployer.address, deployer.address, childToken.address,
            rootToken.address);
        await fxERC20RootTunnel.deployed();

        const FxERC20ChildTunnel = await ethers.getContractFactory("FxERC20ChildTunnel");
        fxERC20ChildTunnel = await FxERC20ChildTunnel.deploy(deployer.address, childToken.address, rootToken.address);
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
            // FxChild as a sender is incorrect
            await expect(
                fxERC20ChildTunnel.connect(signers[1]).processMessageFromRoot(stateId, deployer.address, "0x")
            ).to.be.revertedWith("FxBaseChildTunnel: INVALID_SENDER");

            // FxRoot as a sender is incorrect
            await expect(
                fxERC20ChildTunnel.connect(deployer).processMessageFromRoot(stateId, signers[1].address, "0x")
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

            // Burn tokens on L1 and send message to L2 to retrieve them there
            await expect(
                fxERC20RootTunnel.withdraw(amount)
            ).to.be.reverted;

            // Get the message on L2
            //            const data = ethers.utils.solidityPack(
            //                ["address", "address", "uint256"],
            //                [deployer.address, deployer.address, amount]
            //            );
            const data = ethers.utils.defaultAbiCoder.encode(
                ["address", "address", "uint256"],
                [deployer.address, deployer.address, amount]
            );

            // Upon message receive, tokens on L2 are transferred to the destination account (deployer)
            await fxERC20ChildTunnel.connect(deployer).processMessageFromRoot(stateId, fxERC20RootTunnel.address, data);

            // There must be no balance left locked on the FxERC20ChildTunnel contract
            balance = await childToken.balanceOf(fxERC20ChildTunnel.address);
            expect(balance).to.equal(0);
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
            await rootToken.connect(deployer).approve(fxERC20RootTunnel.address, amount);

            // Root token must be owned by the FxERC20RootTunnel contract
            await rootToken.changeOwner(fxERC20RootTunnel.address);

            // Burn tokens on L1 and send message to L2 to retrieve them there
            await expect(
                fxERC20RootTunnel.withdrawTo(deployer.address, amount)
            ).to.be.reverted;

            // Get the message on L2
            //            const data = ethers.utils.solidityPack(
            //                ["address", "address", "uint256"],
            //                [deployer.address, deployer.address, amount]
            //            );
            const data = ethers.utils.defaultAbiCoder.encode(
                ["address", "address", "uint256"],
                [account.address, deployer.address, amount]
            );

            // Upon message receive, tokens on L2 are transferred to the destination account (deployer)
            await fxERC20ChildTunnel.connect(deployer).processMessageFromRoot(stateId, fxERC20RootTunnel.address, data);

            // There must be no balance left locked on the FxERC20ChildTunnel contract
            balance = await childToken.balanceOf(fxERC20ChildTunnel.address);
            expect(balance).to.equal(0);
        });
    });
});
