/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CM", function () {
    let gnosisSafe;
    let gnosisSafeProxyFactory;
    let multiSend;
    let timelock;
    let treasury;
    let multisig;
    let signers;
    const AddressZero = "0x" + "0".repeat(40);
    const Bytes32Zero = "0x" + "0".repeat(64);
    const safeThreshold = 7;
    beforeEach(async function () {
        const GnosisSafe = await ethers.getContractFactory("GnosisSafe");
        gnosisSafe = await GnosisSafe.deploy();
        await gnosisSafe.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        const MultiSend = await ethers.getContractFactory("MultiSendCallOnly");
        multiSend = await MultiSend.deploy();
        await multiSend.deployed();

        const Timelock = await ethers.getContractFactory("MockTimelockCM");
        timelock = await Timelock.deploy();
        await timelock.deployed();

        const Treasury = await ethers.getContractFactory("MockTreasury");
        treasury = await Treasury.deploy(timelock.address);
        await treasury.deployed();

        signers = await ethers.getSigners();

        // Deploy Safe multisig
        const safeSigners = signers.slice(1, 10).map(
            function (currentElement) {
                return currentElement.address;
            }
        );

        // Create a multisig that will be the service owner
        const safeContracts = require("@gnosis.pm/safe-contracts");
        const setupData = gnosisSafe.interface.encodeFunctionData(
            "setup",
            // signers, threshold, to_address, data, fallback_handler, payment_token, payment, payment_receiver
            [safeSigners, safeThreshold, AddressZero, "0x", AddressZero, AddressZero, 0, AddressZero]
        );
        let proxyAddress = await safeContracts.calculateProxyAddress(gnosisSafeProxyFactory, gnosisSafe.address,
            setupData, 0);
        await gnosisSafeProxyFactory.createProxyWithNonce(gnosisSafe.address, setupData, 0).then((tx) => tx.wait());

        // Get the multisig
        multisig = await ethers.getContractAt("GnosisSafe", proxyAddress);

        const GuardCM = await ethers.getContractFactory("GuardCM");
        guard = await GuardCM.deploy(timelock.address, multisig.address, timelock.address);
        await guard.deployed();
    });

    context("Timelock manipulation via the CM", async function () {
        it("Governance setup: deploy ve, timelock, governor, drop deployer role", async function () {
            const safeContracts = require("@gnosis.pm/safe-contracts");

            // Add timelock as a module
            let nonce = await multisig.nonce();
            let txHashData = await safeContracts.buildContractCall(multisig, "enableModule", [timelock.address], nonce, 0, 0);
            let signMessageData = new Array();
            for (let i = 1; i <= safeThreshold; i++) {
                signMessageData.push(await safeContracts.safeSignMessage(signers[i], multisig, txHashData, 0));
            }
            await safeContracts.executeTx(multisig, txHashData, signMessageData, 0);

            // Construct the payload for the multisig
            //const safePayload = multisig.interface.encodeFunctionData("addOwnerWithThreshold", [signers[15].address, safeThreshold]);
            //const timelockPayload = multisig.interface.encodeFunctionData("execTransactionFromModule", [multisig.address, 0, safePayload, 0]);

            // Construct the payload for the multisig
            let callData = [];
            let txs = [];
            nonce = await multisig.nonce();
            // Add two addresses, and bump the threshold
            for (let i = 0; i < 2; i++) {
                callData[i] = multisig.interface.encodeFunctionData("addOwnerWithThreshold", [signers[15 + i].address, safeThreshold + i + 1]);
                txs[i] = safeContracts.buildSafeTransaction({to: multisig.address, data: callData[i], nonce: 0});
            }

            // Build a multisend transaction to be executed by the service multisig
            const safeTx = safeContracts.buildMultiSendSafeTx(multiSend, txs, nonce);

            // Construct the timelock module transaction
            const timelockPayload = multisig.interface.encodeFunctionData("execTransactionFromModule", [safeTx.to,
                0, safeTx.data, safeTx.operation]);

            const curOwners = await multisig.getOwners();

            // Execute the multisend call via the module
            await timelock.execute(multisig.address, timelockPayload);

            const newOwners = await multisig.getOwners();

            // There must be two new owners in addition to the original ones
            expect(newOwners.length).to.equal(curOwners.length + 2);
        });

        it.only("CM Guard", async function () {
            const safeContracts = require("@gnosis.pm/safe-contracts");

            // Setting the CM guard
            let nonce = await multisig.nonce();
            let txHashData = await safeContracts.buildContractCall(multisig, "setGuard", [guard.address], nonce, 0, 0);
            let signMessageData = new Array();
            for (let i = 1; i <= safeThreshold; i++) {
                signMessageData.push(await safeContracts.safeSignMessage(signers[i], multisig, txHashData, 0));
            }
            await safeContracts.executeTx(multisig, txHashData, signMessageData, 0);

            // Authorize treasury target and selector
            // bytes32(keccak256("pause")) == 0x8456cb59
            const setTargetSelectorsPayload = guard.interface.encodeFunctionData("setTargetSelectors",
                [[treasury.address], ["0x8456cb59"], [true]]);
            await timelock.execute(guard.address, setTargetSelectorsPayload);

            // Create a payload data for the schedule function
            const payload = treasury.interface.encodeFunctionData("pause");

            // Prepare the CM schedule function call
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(timelock, "schedule", [treasury.address, 0, payload,
                  Bytes32Zero, Bytes32Zero, 0], nonce, 0, 0);
            for (let i = 0; i < safeThreshold; i++) {
                signMessageData[i] = await safeContracts.safeSignMessage(signers[i+1], multisig, txHashData, 0);
            }
            await safeContracts.executeTx(multisig, txHashData, signMessageData, 0);

            // Execute after the schedule
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(timelock, "execute", [treasury.address, payload], nonce, 0, 0);
            for (let i = 0; i < safeThreshold; i++) {
                signMessageData[i] = await safeContracts.safeSignMessage(signers[i+1], multisig, txHashData, 0);
            }
            await safeContracts.executeTx(multisig, txHashData, signMessageData, 0);

            // Check that the treasury is paused
            const pausedTreasury = await treasury.paused();
            expect(pausedTreasury).to.eq(2);
        });
    });
});
