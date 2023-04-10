/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("FxGovernorTunnel", function () {
    let fxGovernorTunnel;
    let signers;
    let deployer;
    const AddressZero = ethers.constants.AddressZero;
    const stateId = 0;

    beforeEach(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];

        const FxGovernorTunnel = await ethers.getContractFactory("FxGovernorTunnel");
        fxGovernorTunnel = await FxGovernorTunnel.deploy(deployer.address, deployer.address);
        await fxGovernorTunnel.deployed();
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

        it("Should fail when trying to call with the incorrectly provided payload", async function () {
            const OLAS = await ethers.getContractFactory("OLAS");
            const olas = await OLAS.deploy();
            await olas.deployed();

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
            const OLAS = await ethers.getContractFactory("OLAS");
            const olas = await OLAS.deploy();
            await olas.deployed();
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
            const OLAS = await ethers.getContractFactory("OLAS");
            const olas = await OLAS.deploy();
            await olas.deployed();
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
    });
});
