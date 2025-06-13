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
    });

    context("Process data", async function () {

    });
});
