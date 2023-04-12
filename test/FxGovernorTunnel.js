/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("FxGovernorTunnel", function () {
    let fxGovernorTunnel;
    let olas;
    let signers;
    let deployer;
    const AddressZero = ethers.constants.AddressZero;
    const stateId = 0;

    beforeEach(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];

        // The deployer is the analogue of the Timelock on L1 and the FxRoot mock on L1 as well
        const FxGovernorTunnel = await ethers.getContractFactory("FxGovernorTunnel");
        fxGovernorTunnel = await FxGovernorTunnel.deploy(deployer.address, deployer.address);
        await fxGovernorTunnel.deployed();

        // OLAS represents a contract deployed on L2
        const OLAS = await ethers.getContractFactory("OLAS");
        olas = await OLAS.deploy();
        await olas.deployed();
    });

    context("Initialization", async function () {
        it("Deploying with zero addresses", async function () {
            const FxGovernorTunnel = await ethers.getContractFactory("FxGovernorTunnel");
            await expect(
                FxGovernorTunnel.deploy(AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(fxGovernorTunnel, "ZeroAddress");

            await expect(
                FxGovernorTunnel.deploy(signers[1].address, AddressZero)
            ).to.be.revertedWithCustomError(fxGovernorTunnel, "ZeroAddress");
        });
    });

    context("Process message from root", async function () {
        it("Should fail when trying to call from incorrect contract addresses", async function () {
            await expect(
                fxGovernorTunnel.connect(signers[1]).processMessageFromRoot(stateId, deployer.address, "0x")
            ).to.be.revertedWithCustomError(fxGovernorTunnel, "FxChildOnly");

            await expect(
                fxGovernorTunnel.connect(deployer).processMessageFromRoot(stateId, signers[1].address, "0x")
            ).to.be.revertedWithCustomError(fxGovernorTunnel, "RootGovernorOnly");
        });

        it("Should fail when trying to process message with the incorrect minimal payload length", async function () {
            await expect(
                fxGovernorTunnel.connect(deployer).processMessageFromRoot(stateId, deployer.address, "0x")
            ).to.be.revertedWithCustomError(fxGovernorTunnel, "IncorrectDataLength");
        });

        it("Should fail when trying to change the root governor from any other contract / EOA", async function () {
            await expect(
                fxGovernorTunnel.connect(deployer).changeRootGovernor(signers[1].address)
            ).to.be.revertedWithCustomError(fxGovernorTunnel, "SelfCallOnly");
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
                fxGovernorTunnel.connect(deployer).processMessageFromRoot(stateId, deployer.address, data)
            ).to.be.revertedWithCustomError(fxGovernorTunnel, "ZeroAddress");
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
                fxGovernorTunnel.connect(deployer).processMessageFromRoot(stateId, deployer.address, data)
            ).to.be.revertedWithCustomError(fxGovernorTunnel, "TargetExecFailed");
        });

        it("Unpack the data and call one specified target on the OLAS contract", async function () {
            // Minter of OLAS must be the fxGovernorTunnel contract
            await olas.connect(deployer).changeMinter(fxGovernorTunnel.address);

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
            await fxGovernorTunnel.connect(deployer).processMessageFromRoot(stateId, deployer.address, data);

            // Check that OLAS tokens were minted to the deployer
            const balance = Number(await olas.balanceOf(deployer.address));
            expect(balance).to.equal(amountToMint);
        });

        it("Unpack the data and call two specified targets on the OLAS contract", async function () {
            // Minter of OLAS must be the fxGovernorTunnel contract
            await olas.connect(deployer).changeMinter(fxGovernorTunnel.address);
            // Change OLAS owner to the fxGovernorTunnel contract
            await olas.connect(deployer).changeOwner(fxGovernorTunnel.address);

            // FxGivernorTunnel changes the minter to self as being the owner, then mint 100 OLAS for the deployer
            const amountToMint = 100;
            const payloads = [olas.interface.encodeFunctionData("changeMinter", [fxGovernorTunnel.address]),
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
            await fxGovernorTunnel.connect(deployer).processMessageFromRoot(stateId, deployer.address, data);

            // Check that OLAS tokens were minted to the deployer
            const balance = Number(await olas.balanceOf(deployer.address));
            expect(balance).to.equal(amountToMint);
        });

        it("Change the root governor", async function () {
            const rawPayload = fxGovernorTunnel.interface.encodeFunctionData("changeRootGovernor", [signers[1].address]);

            // Pack the data into one contiguous buffer
            const target = fxGovernorTunnel.address;
            const value = 0;
            const payload = ethers.utils.arrayify(rawPayload);
            const data = ethers.utils.solidityPack(
                ["address", "uint96", "uint32", "bytes"],
                [target, value, payload.length, payload]
            );

            // Execute the unpacked transaction
            await fxGovernorTunnel.connect(deployer).processMessageFromRoot(stateId, deployer.address, data);

            // Check that the new root governor is signers[1].address
            const rootGovernor = await fxGovernorTunnel.rootGovernor();
            expect(rootGovernor).to.equal(signers[1].address);
        });

        it("Should fail when trying to change the root governor to the zero address", async function () {
            const rawPayload = fxGovernorTunnel.interface.encodeFunctionData("changeRootGovernor", [AddressZero]);

            // Pack the data into one contiguous buffer
            const target = fxGovernorTunnel.address;
            const value = 0;
            const payload = ethers.utils.arrayify(rawPayload);
            const data = ethers.utils.solidityPack(
                ["address", "uint96", "uint32", "bytes"],
                [target, value, payload.length, payload]
            );

            // Execute the unpacked transaction
            await expect(
                fxGovernorTunnel.connect(deployer).processMessageFromRoot(stateId, deployer.address, data)
            ).to.be.revertedWithCustomError(fxGovernorTunnel, "TargetExecFailed");
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
                fxGovernorTunnel.connect(deployer).processMessageFromRoot(stateId, deployer.address, data)
            ).to.be.revertedWithCustomError(fxGovernorTunnel, "InsufficientBalance");

            // Send funds to the contract
            await deployer.sendTransaction({to: fxGovernorTunnel.address, value: amount});

            // Now the funds can be transferred
            const balanceBefore = await ethers.provider.getBalance(deployer.address);
            const tx = await fxGovernorTunnel.connect(deployer).processMessageFromRoot(stateId, deployer.address, data);
            const receipt = await tx.wait();
            const gasCost = ethers.BigNumber.from(receipt.gasUsed).mul(ethers.BigNumber.from(tx.gasPrice));
            const balanceAfter = await ethers.provider.getBalance(deployer.address);
            const balanceDiff = balanceAfter.sub(balanceBefore).add(gasCost);
            expect(balanceDiff).to.equal(amount);
        });

        it("Unpack the data and call one specified target to send funds and to mint OLAS", async function () {
            const amount = ethers.utils.parseEther("1");
            const amountToMint = 100;
            // Minter of OLAS must be the fxGovernorTunnel contract
            await olas.connect(deployer).changeMinter(fxGovernorTunnel.address);

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
            await deployer.sendTransaction({to: fxGovernorTunnel.address, value: amount});

            // Execute the function and check for the deployer balance
            const balanceBefore = await ethers.provider.getBalance(deployer.address);
            const tx = await fxGovernorTunnel.connect(deployer).processMessageFromRoot(stateId, deployer.address, data);
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
