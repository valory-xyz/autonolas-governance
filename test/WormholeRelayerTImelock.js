/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("WormholeRelayerTimelock", function () {
    let timelock;
    let wormholeRelayer;
    let wormholeRelayerTimelock;
    let signers;
    let deployer;
    const AddressZero = ethers.constants.AddressZero;
    const Bytes32Zero = ethers.constants.HashZero;
    const targetChain = 2;
    const targetAddress = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
    const payload = "0x1234";
    const receiverValue = ethers.utils.parseEther("1");
    const gasLimit = 100000;
    const refundChain = 1;
    const refundChainAddress = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC";
    const refundValueAddress = "0x90F79bf6EB2c4f870365E785982E1f101E93b906";

    beforeEach(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];

        // Deploy mock of Timelock contract
        const Timelock = await ethers.getContractFactory("MockTimelock");
        timelock = await Timelock.deploy(deployer.address);
        await timelock.deployed();

        // Deploy mock of WormholeRelayer
        const WormholeRelayer = await ethers.getContractFactory("MockWormholeRelayer");
        wormholeRelayer = await WormholeRelayer.deploy();
        await wormholeRelayer.deployed();

        // Deploy Wormhole Relayer Timelock
        const WormholeRelayerTimelock = await ethers.getContractFactory("WormholeRelayerTimelock");
        wormholeRelayerTimelock = await WormholeRelayerTimelock.deploy(timelock.address, wormholeRelayer.address);
        await wormholeRelayerTimelock.deployed();
    });

    context("Initialization", async function () {
        it("Deploying with zero addresses", async function () {
            const WormholeRelayerTimelock = await ethers.getContractFactory("WormholeRelayerTimelock");
            await expect(
                WormholeRelayerTimelock.deploy(AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(wormholeRelayerTimelock, "ZeroAddress");
            await expect(
                WormholeRelayerTimelock.deploy(timelock.address, AddressZero)
            ).to.be.revertedWithCustomError(wormholeRelayerTimelock, "ZeroAddress");
        });

        it("Should set correct initial values", async function () {
            expect(await wormholeRelayerTimelock.timelock()).to.equal(timelock.address);
            expect(await wormholeRelayerTimelock.wormholeRelayer()).to.equal(wormholeRelayer.address);
        });
    });

    context("sendPayloadToEvm", async function () {
        it("Should revert when called by non-timelock", async function () {
            await expect(
                wormholeRelayerTimelock.sendPayloadToEvm(
                    targetChain,
                    targetAddress,
                    payload,
                    receiverValue,
                    gasLimit,
                    refundChain,
                    refundChainAddress,
                    refundValueAddress,
                    { value: ethers.utils.parseEther("2") }
                )
            ).to.be.revertedWithCustomError(wormholeRelayerTimelock, "UnauthorizedAccount")
                .withArgs(deployer.address);
        });

        it("Should revert with zero target address", async function () {
            const calldata = wormholeRelayerTimelock.interface.encodeFunctionData("sendPayloadToEvm", [
                targetChain,
                AddressZero,
                payload,
                receiverValue,
                gasLimit,
                refundChain,
                refundChainAddress,
                refundValueAddress
            ]);

            await expect(
                timelock.executeCustomRelayer(wormholeRelayerTimelock.address, calldata, { value: ethers.utils.parseEther("2") })
            ).to.be.reverted;
        });

        it("Should revert with zero refund chain address", async function () {
            const calldata = wormholeRelayerTimelock.interface.encodeFunctionData("sendPayloadToEvm", [
                targetChain,
                targetAddress,
                payload,
                receiverValue,
                gasLimit,
                refundChain,
                AddressZero,
                refundValueAddress
            ]);

            await expect(
                timelock.executeCustomRelayer(wormholeRelayerTimelock.address, calldata, { value: ethers.utils.parseEther("2") })
            ).to.be.reverted;
        });

        it("Should revert with zero values", async function () {
            // Test zero target chain
            let calldata = wormholeRelayerTimelock.interface.encodeFunctionData("sendPayloadToEvm", [
                0,
                targetAddress,
                payload,
                receiverValue,
                gasLimit,
                refundChain,
                refundChainAddress,
                refundValueAddress
            ]);

            await expect(
                timelock.executeCustomRelayer(wormholeRelayerTimelock.address, calldata, { value: ethers.utils.parseEther("2") })
            ).to.be.reverted;

            // Test zero payload
            calldata = wormholeRelayerTimelock.interface.encodeFunctionData("sendPayloadToEvm", [
                targetChain,
                targetAddress,
                "0x",
                receiverValue,
                gasLimit,
                refundChain,
                refundChainAddress,
                refundValueAddress
            ]);

            await expect(
                timelock.executeCustomRelayer(wormholeRelayerTimelock.address, calldata, { value: ethers.utils.parseEther("2") })
            ).to.be.reverted;

            // Test zero gas limit
            calldata = wormholeRelayerTimelock.interface.encodeFunctionData("sendPayloadToEvm", [
                targetChain,
                targetAddress,
                payload,
                receiverValue,
                0,
                refundChain,
                refundChainAddress,
                refundValueAddress
            ]);

            await expect(
                timelock.executeCustomRelayer(wormholeRelayerTimelock.address, calldata, { value: ethers.utils.parseEther("2") })
            ).to.be.reverted;

            // Test zero refund chain
            calldata = wormholeRelayerTimelock.interface.encodeFunctionData("sendPayloadToEvm", [
                targetChain,
                targetAddress,
                payload,
                receiverValue,
                gasLimit,
                0,
                refundChainAddress,
                refundValueAddress
            ]);

            await expect(
                timelock.executeCustomRelayer(wormholeRelayerTimelock.address, calldata, { value: ethers.utils.parseEther("2") })
            ).to.be.reverted;
        });

        it("Should revert when msg.value is less than cost", async function () {
            const calldata = wormholeRelayerTimelock.interface.encodeFunctionData("sendPayloadToEvm", [
                targetChain,
                targetAddress,
                payload,
                receiverValue,
                gasLimit,
                refundChain,
                refundChainAddress,
                refundValueAddress
            ]);

            await expect(
                timelock.executeCustomRelayer(wormholeRelayerTimelock.address, calldata, { value: 1 })
            ).to.be.reverted;
        });

        it("Should use tx.origin as refund address when refundValueAddress is zero", async function () {
            const cost = await wormholeRelayer.COST();
            const msgValue = cost.add(1);
            const expectedLeftovers = msgValue.sub(cost);

            const calldata = wormholeRelayerTimelock.interface.encodeFunctionData("sendPayloadToEvm", [
                targetChain,
                targetAddress,
                payload,
                receiverValue,
                gasLimit,
                refundChain,
                refundChainAddress,
                AddressZero
            ]);

            await expect(
                timelock.executeCustomRelayer(wormholeRelayerTimelock.address, calldata, { value: msgValue })
            ).to.emit(wormholeRelayerTimelock, "LeftoversRefunded")
                .withArgs(deployer.address, expectedLeftovers);
        });

        it("Should use timelock as refund address when refundValueAddress is zero", async function () {
            const cost = await wormholeRelayer.COST();
            const msgValue = cost.add(1);
            const expectedLeftovers = msgValue.sub(cost);

            const calldata = wormholeRelayerTimelock.interface.encodeFunctionData("sendPayloadToEvm", [
                targetChain,
                targetAddress,
                payload,
                receiverValue,
                gasLimit,
                refundChain,
                refundChainAddress,
                timelock.address
            ]);

            await expect(
                timelock.executeCustomRelayer(wormholeRelayerTimelock.address, calldata, { value: msgValue })
            ).to.emit(wormholeRelayerTimelock, "LeftoversRefunded")
                .withArgs(timelock.address, expectedLeftovers);
        });

        it("No leftovers", async function () {
            const msgValue = await wormholeRelayer.COST();

            const calldata = wormholeRelayerTimelock.interface.encodeFunctionData("sendPayloadToEvm", [
                targetChain,
                targetAddress,
                payload,
                receiverValue,
                gasLimit,
                refundChain,
                refundChainAddress,
                AddressZero
            ]);

            await expect(
                timelock.executeCustomRelayer(wormholeRelayerTimelock.address, calldata, { value: msgValue })
            ).to.not.emit(wormholeRelayerTimelock, "LeftoversRefunded");
        });
    });
});
