/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CM", function () {
    let gnosisSafe;
    let gnosisSafeProxyFactory;
    let multiSend;
    let timelock;
    let signers;
    const AddressZero = "0x" + "0".repeat(40);
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

        // Dispenser address is irrelevant in these tests, so its contract is passed as a zero address
        const Timelock = await ethers.getContractFactory("MockTimelockCM");
        timelock = await Timelock.deploy();
        await timelock.deployed();

        signers = await ethers.getSigners();
    });

    context("Initialization", async function () {
        it("Governance setup: deploy ve, timelock, governor, drop deployer role", async function () {
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
            const multisig = await ethers.getContractAt("GnosisSafe", proxyAddress);

            // Set the multisig address to be called from the timelock
            await timelock.setMultisig(multisig.address);

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
            await timelock.execute(timelockPayload);

            const newOwners = await multisig.getOwners();

            // There must be two new owners in addition to the original ones
            expect(newOwners.length).to.equal(curOwners.length + 2);
        });
    });
});
