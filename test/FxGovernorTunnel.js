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
    });
});
