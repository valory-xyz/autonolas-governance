/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("OptimismMessenger", function () {
    let cdmContractProxy;
    let optimismMessenger;
    let olas;
    let signers;
    let deployer;
    const AddressZero = ethers.constants.AddressZero;

    beforeEach(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];

        // Deploy the mock of CDMContractProxy contract
        const CDMContractProxy = await ethers.getContractFactory("MockL2Relayer");
        cdmContractProxy = await CDMContractProxy.deploy(deployer.address, deployer.address);
        await cdmContractProxy.deployed();

        // The deployer is the analogue of the Timelock on L1 and the FxRoot mock on L1 as well
        const OptimismMessenger = await ethers.getContractFactory("OptimismMessenger");
        optimismMessenger = await OptimismMessenger.deploy(cdmContractProxy.address, deployer.address);
        await optimismMessenger.deployed();

        // Change the OptimismMessenger contract address in the CDMContractProxy
        await cdmContractProxy.changeBridgeMessenger(optimismMessenger.address);

        // OLAS represents a contract deployed on L2
        const OLAS = await ethers.getContractFactory("OLAS");
        olas = await OLAS.deploy();
        await olas.deployed();
    });

    context("Initialization", async function () {
        it("Deploying with zero addresses", async function () {
            const OptimismMessenger = await ethers.getContractFactory("OptimismMessenger");
            await expect(
                OptimismMessenger.deploy(AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(optimismMessenger, "ZeroAddress");

            await expect(
                OptimismMessenger.deploy(signers[1].address, AddressZero)
            ).to.be.revertedWithCustomError(optimismMessenger, "ZeroAddress");
        });
    });

    context("Process message from source", async function () {
        it("Should fail when trying to call from incorrect contract addresses", async function () {
            await expect(
                optimismMessenger.connect(deployer).processMessageFromSource("0x")
            ).to.be.revertedWithCustomError(optimismMessenger, "TargetRelayerOnly");

            // Simulate incorrect sourceGovernor address
            await cdmContractProxy.changeSourceGovernor(AddressZero);
            await expect(
                cdmContractProxy.processMessageFromSource("0x")
            ).to.be.revertedWithCustomError(optimismMessenger, "SourceGovernorOnly");
        });

        it("Should fail when trying to process message with the incorrect minimal payload length", async function () {
            await expect(
                cdmContractProxy.processMessageFromSource("0x")
            ).to.be.revertedWithCustomError(optimismMessenger, "IncorrectDataLength");
        });

        it("Should fail when trying to change the source governor from any other contract / EOA", async function () {
            await expect(
                optimismMessenger.connect(deployer).changeSourceGovernor(signers[1].address)
            ).to.be.revertedWithCustomError(optimismMessenger, "SelfCallOnly");
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
                cdmContractProxy.processMessageFromSource(data)
            ).to.be.revertedWithCustomError(optimismMessenger, "ZeroAddress");
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
                cdmContractProxy.processMessageFromSource(data)
            ).to.be.revertedWithCustomError(optimismMessenger, "TargetExecFailed");
        });

        it("Unpack the data and call one specified target on the OLAS contract", async function () {
            // Minter of OLAS must be the optimismMessenger contract
            await olas.connect(deployer).changeMinter(optimismMessenger.address);

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
            await cdmContractProxy.processMessageFromSource(data);

            // Check that OLAS tokens were minted to the deployer
            const balance = Number(await olas.balanceOf(deployer.address));
            expect(balance).to.equal(amountToMint);
        });

        it("Unpack the data and call two specified targets on the OLAS contract", async function () {
            // Minter of OLAS must be the optimismMessenger contract
            await olas.connect(deployer).changeMinter(optimismMessenger.address);
            // Change OLAS owner to the optimismMessenger contract
            await olas.connect(deployer).changeOwner(optimismMessenger.address);

            // FxGivernorTunnel changes the minter to self as being the owner, then mint 100 OLAS for the deployer
            const amountToMint = 100;
            const payloads = [olas.interface.encodeFunctionData("changeMinter", [optimismMessenger.address]),
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
            await cdmContractProxy.processMessageFromSource(data);

            // Check that OLAS tokens were minted to the deployer
            const balance = Number(await olas.balanceOf(deployer.address));
            expect(balance).to.equal(amountToMint);
        });

        it("Change the source governor", async function () {
            const rawPayload = optimismMessenger.interface.encodeFunctionData("changeSourceGovernor", [signers[1].address]);

            // Pack the data into one contiguous buffer
            const target = optimismMessenger.address;
            const value = 0;
            const payload = ethers.utils.arrayify(rawPayload);
            const data = ethers.utils.solidityPack(
                ["address", "uint96", "uint32", "bytes"],
                [target, value, payload.length, payload]
            );

            // Execute the unpacked transaction
            await cdmContractProxy.processMessageFromSource(data);

            // Check that the new source governor is signers[1].address
            const sourceGovernor = await optimismMessenger.sourceGovernor();
            expect(sourceGovernor).to.equal(signers[1].address);
        });

        it("Should fail when trying to change the source governor to the zero address", async function () {
            const rawPayload = optimismMessenger.interface.encodeFunctionData("changeSourceGovernor", [AddressZero]);

            // Pack the data into one contiguous buffer
            const target = optimismMessenger.address;
            const value = 0;
            const payload = ethers.utils.arrayify(rawPayload);
            const data = ethers.utils.solidityPack(
                ["address", "uint96", "uint32", "bytes"],
                [target, value, payload.length, payload]
            );

            // Execute the unpacked transaction
            await expect(
                cdmContractProxy.processMessageFromSource(data)
            ).to.be.revertedWithCustomError(optimismMessenger, "TargetExecFailed");
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
                cdmContractProxy.processMessageFromSource(data)
            ).to.be.revertedWithCustomError(optimismMessenger, "InsufficientBalance");

            // Send funds to the contract
            await deployer.sendTransaction({to: optimismMessenger.address, value: amount});

            // Now the funds can be transferred
            const balanceBefore = await ethers.provider.getBalance(deployer.address);
            const tx = await cdmContractProxy.processMessageFromSource(data);
            const receipt = await tx.wait();
            const gasCost = ethers.BigNumber.from(receipt.gasUsed).mul(ethers.BigNumber.from(tx.gasPrice));
            const balanceAfter = await ethers.provider.getBalance(deployer.address);
            const balanceDiff = balanceAfter.sub(balanceBefore).add(gasCost);
            expect(balanceDiff).to.equal(amount);
        });

        it("Unpack the data and call one specified target to send funds and to mint OLAS", async function () {
            const amount = ethers.utils.parseEther("1");
            const amountToMint = 100;
            // Minter of OLAS must be the optimismMessenger contract
            await olas.connect(deployer).changeMinter(optimismMessenger.address);

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
            await deployer.sendTransaction({to: optimismMessenger.address, value: amount});

            // Execute the function and check for the deployer balance
            const balanceBefore = await ethers.provider.getBalance(deployer.address);
            const tx = await cdmContractProxy.processMessageFromSource(data);
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
