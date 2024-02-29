/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("WormholeMessenger", function () {
    let targetRelayer;
    let wormholeMessenger;
    let olas;
    let signers;
    let deployer;
    const AddressZero = ethers.constants.AddressZero;
    const Bytes32Zero = "0x" + "0".repeat(64);
    const sourceChain = 2;
    const addressPrefix = "0x" + "0".repeat(24);

    beforeEach(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];

        // Deploy the mock of TargetRelayer contract
        const TargetRelayer = await ethers.getContractFactory("MockL2Relayer");
        targetRelayer = await TargetRelayer.deploy(deployer.address, deployer.address);
        await targetRelayer.deployed();

        // The deployer is the analogue of the Timelock on L1 and the FxRoot mock on L1 as well
        const WormholeMessenger = await ethers.getContractFactory("WormholeMessenger");
        wormholeMessenger = await WormholeMessenger.deploy(targetRelayer.address,
            addressPrefix + deployer.address.slice(2), sourceChain);
        await wormholeMessenger.deployed();

        // Change the WormholeMessenger contract address in the TargetRelayer
        await targetRelayer.changeBridgeMessenger(wormholeMessenger.address);

        // OLAS represents a contract deployed on L2
        const OLAS = await ethers.getContractFactory("OLAS");
        olas = await OLAS.deploy();
        await olas.deployed();
    });

    context("Initialization", async function () {
        it("Deploying with zero addresses", async function () {
            const WormholeMessenger = await ethers.getContractFactory("WormholeMessenger");
            await expect(
                WormholeMessenger.deploy(AddressZero, Bytes32Zero, 0)
            ).to.be.revertedWithCustomError(wormholeMessenger, "ZeroAddress");

            await expect(
                WormholeMessenger.deploy(signers[1].address, Bytes32Zero, 0)
            ).to.be.revertedWithCustomError(wormholeMessenger, "ZeroValue");

            await expect(
                WormholeMessenger.deploy(signers[1].address, addressPrefix + signers[2].address.slice(2), 0)
            ).to.be.revertedWithCustomError(wormholeMessenger, "ZeroValue");
        });
    });

    context("Process message from source", async function () {
        it("Should fail when trying to call from incorrect contract addresses and chain Id", async function () {
            await expect(
                wormholeMessenger.connect(deployer).receiveWormholeMessages("0x", [], Bytes32Zero, 0, Bytes32Zero)
            ).to.be.revertedWithCustomError(wormholeMessenger, "TargetRelayerOnly");

            // Simulate incorrect sourceGovernor address
            await targetRelayer.changeSourceGovernor(AddressZero);
            await expect(
                targetRelayer.receiveWormholeMessages("0x")
            ).to.be.revertedWithCustomError(wormholeMessenger, "SourceGovernorOnly32");

            // Simulate incorrect source chain Id
            await targetRelayer.changeSourceChain(0);
            await expect(
                targetRelayer.receiveWormholeMessages("0x")
            ).to.be.revertedWithCustomError(wormholeMessenger, "WrongSourceChainId");
        });

        it("Should fail when trying to process message with the incorrect minimal payload length", async function () {
            await expect(
                targetRelayer.receiveWormholeMessages("0x")
            ).to.be.revertedWithCustomError(wormholeMessenger, "IncorrectDataLength");
        });

        it("Should fail when trying to change the source governor from any other contract / EOA", async function () {
            await expect(
                wormholeMessenger.connect(deployer).changeSourceGovernor(addressPrefix + signers[1].address.slice(2))
            ).to.be.revertedWithCustomError(wormholeMessenger, "SelfCallOnly");
        });

        it("Should fail when trying to call with the zero address", async function () {
            const target = AddressZero;
            const value = 0;
            const payload = "";
            const data = ethers.utils.solidityPack(
                ["address", "uint96", "uint32"],
                [target, value, payload.length]
            );

            await expect(
                targetRelayer.receiveWormholeMessages(data)
            ).to.be.revertedWithCustomError(wormholeMessenger, "ZeroAddress");
        });

        it("Should fail when trying to call with the incorrectly provided payload", async function () {
            const target = olas.address;
            const value = 0;
            const rawPayload = "0x" + "abcd".repeat(10);
            const payload = ethers.utils.arrayify(rawPayload);
            const data = ethers.utils.solidityPack(
                ["address", "uint96", "uint32", "bytes"],
                [target, value, payload.length, payload]
            );

            await expect(
                targetRelayer.receiveWormholeMessages(data)
            ).to.be.revertedWithCustomError(wormholeMessenger, "TargetExecFailed");
        });

        it("Unpack the data and call one specified target on the OLAS contract", async function () {
            // Minter of OLAS must be the wormholeMessenger contract
            await olas.connect(deployer).changeMinter(wormholeMessenger.address);

            // OLAS contract across the bridge must mint 100 OLAS for the deployer
            const amountToMint = 100;
            const rawPayload = olas.interface.encodeFunctionData("mint", [deployer.address, amountToMint]);

            // Pack the data into one contiguous buffer
            const target = olas.address;
            const value = 0;
            const payload = ethers.utils.arrayify(rawPayload);
            const data = ethers.utils.solidityPack(
                ["address", "uint96", "uint32", "bytes"],
                [target, value, payload.length, payload]
            );

            // Execute the unpacked transaction
            await targetRelayer.receiveWormholeMessages(data);

            // Check that OLAS tokens were minted to the deployer
            const balance = Number(await olas.balanceOf(deployer.address));
            expect(balance).to.equal(amountToMint);

            // Try to unpack with the same delivery hash
            await expect(
                targetRelayer.receiveWormholeMessages(data)
            ).to.be.revertedWithCustomError(wormholeMessenger, "AlreadyDelivered");
        });

        it("Unpack the data and call two specified targets on the OLAS contract", async function () {
            // Minter of OLAS must be the wormholeMessenger contract
            await olas.connect(deployer).changeMinter(wormholeMessenger.address);
            // Change OLAS owner to the wormholeMessenger contract
            await olas.connect(deployer).changeOwner(wormholeMessenger.address);

            // FxGivernorTunnel changes the minter to self as being the owner, then mint 100 OLAS for the deployer
            const amountToMint = 100;
            const payloads = [olas.interface.encodeFunctionData("changeMinter", [wormholeMessenger.address]),
                olas.interface.encodeFunctionData("mint", [deployer.address, amountToMint])];

            // Pack the data into one contiguous buffer
            const targets = [olas.address, olas.address];
            const values = [0, 0];
            let data = "0x";
            for (let i = 0; i < targets.length; i++) {
                const payload = ethers.utils.arrayify(payloads[i]);
                const encoded = ethers.utils.solidityPack(
                    ["address", "uint96", "uint32", "bytes"],
                    [targets[i], values[i], payload.length, payload]
                );
                data += encoded.slice(2);
            }

            // Execute the unpacked transaction
            await targetRelayer.receiveWormholeMessages(data);

            // Check that OLAS tokens were minted to the deployer
            const balance = Number(await olas.balanceOf(deployer.address));
            expect(balance).to.equal(amountToMint);
        });

        it("Change the source governor", async function () {
            const rawPayload = wormholeMessenger.interface.encodeFunctionData("changeSourceGovernor",
                [addressPrefix + signers[1].address.slice(2)]);

            // Pack the data into one contiguous buffer
            const target = wormholeMessenger.address;
            const value = 0;
            const payload = ethers.utils.arrayify(rawPayload);
            const data = ethers.utils.solidityPack(
                ["address", "uint96", "uint32", "bytes"],
                [target, value, payload.length, payload]
            );

            // Execute the unpacked transaction
            await targetRelayer.receiveWormholeMessages(data);

            // Check that the new source governor is signers[1].address
            const sourceGovernor = await wormholeMessenger.sourceGovernor();
            expect(sourceGovernor).to.equal((addressPrefix + signers[1].address.slice(2)).toLowerCase());
        });

        it("Should fail when trying to change the source governor to the zero address", async function () {
            const rawPayload = wormholeMessenger.interface.encodeFunctionData("changeSourceGovernor", [Bytes32Zero]);

            // Pack the data into one contiguous buffer
            const target = wormholeMessenger.address;
            const value = 0;
            const payload = ethers.utils.arrayify(rawPayload);
            const data = ethers.utils.solidityPack(
                ["address", "uint96", "uint32", "bytes"],
                [target, value, payload.length, payload]
            );

            // Execute the unpacked transaction
            await expect(
                targetRelayer.receiveWormholeMessages(data)
            ).to.be.revertedWithCustomError(wormholeMessenger, "TargetExecFailed");
        });

        it("Unpack the data and call one specified target to send funds", async function () {
            const amount = ethers.utils.parseEther("1");
            // Pack the data into one contiguous buffer
            const target = deployer.address;
            const value = amount;
            const payloadLength = 0;
            const data = ethers.utils.solidityPack(
                ["address", "uint96", "uint32"],
                [target, value, payloadLength]
            );

            // Try to execute the unpacked transaction without the contract having enough balance
            await expect(
                targetRelayer.receiveWormholeMessages(data)
            ).to.be.revertedWithCustomError(wormholeMessenger, "InsufficientBalance");

            // Send funds to the contract
            await deployer.sendTransaction({to: wormholeMessenger.address, value: amount});

            // Now the funds can be transferred
            const balanceBefore = await ethers.provider.getBalance(deployer.address);
            const tx = await targetRelayer.receiveWormholeMessages(data);
            const receipt = await tx.wait();
            const gasCost = ethers.BigNumber.from(receipt.gasUsed).mul(ethers.BigNumber.from(tx.gasPrice));
            const balanceAfter = await ethers.provider.getBalance(deployer.address);
            const balanceDiff = balanceAfter.sub(balanceBefore).add(gasCost);
            expect(balanceDiff).to.equal(amount);
        });

        it("Unpack the data and call one specified target to send funds and to mint OLAS", async function () {
            const amount = ethers.utils.parseEther("1");
            const amountToMint = 100;
            // Minter of OLAS must be the wormholeMessenger contract
            await olas.connect(deployer).changeMinter(wormholeMessenger.address);

            // Pack the first part of data with the zero payload
            let target = deployer.address;
            let value = amount;
            const payloadLength = 0;
            let data = ethers.utils.solidityPack(
                ["address", "uint96", "uint32"],
                [target, value, payloadLength]
            );

            // OLAS contract across the bridge must mint 100 OLAS for the deployer
            const rawPayload = olas.interface.encodeFunctionData("mint", [deployer.address, amountToMint]);
            // Pack the second part of data
            target = olas.address;
            value = 0;
            const payload = ethers.utils.arrayify(rawPayload);
            data += ethers.utils.solidityPack(
                ["address", "uint96", "uint32", "bytes"],
                [target, value, payload.length, payload]
            ).slice(2);

            // Send funds to the contract
            await deployer.sendTransaction({to: wormholeMessenger.address, value: amount});

            // Execute the function and check for the deployer balance
            const balanceBefore = await ethers.provider.getBalance(deployer.address);
            const tx = await targetRelayer.receiveWormholeMessages(data);
            const receipt = await tx.wait();
            const gasCost = ethers.BigNumber.from(receipt.gasUsed).mul(ethers.BigNumber.from(tx.gasPrice));
            const balanceAfter = await ethers.provider.getBalance(deployer.address);
            const balanceDiff = balanceAfter.sub(balanceBefore).add(gasCost);
            expect(balanceDiff).to.equal(amount);

            // Check that OLAS tokens were minted to the deployer
            const olasBalance = Number(await olas.balanceOf(deployer.address));
            expect(olasBalance).to.equal(amountToMint);
        });
    });
});
