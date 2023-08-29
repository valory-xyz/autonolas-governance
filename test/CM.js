/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-network-helpers");
const safeContracts = require("@gnosis.pm/safe-contracts");

describe("Community Multisig", function () {
    let gnosisSafe;
    let gnosisSafeProxyFactory;
    let multiSend;
    let timelock;
    let treasury;
    let multisig;
    let guard;
    let olas;
    let ve;
    let governor;
    let signers;
    let deployer;
    const AddressZero = "0x" + "0".repeat(40);
    const Bytes32Zero = "0x" + "0".repeat(64);
    const safeThreshold = 7;
    const initialVotingDelay = 5;
    const initialVotingPeriod = 10;
    const initialProposalThreshold = ethers.utils.parseEther("5");
    const quorum = 1;

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
        deployer = signers[0];

        // Deploy Safe multisig
        const safeSigners = signers.slice(1, 10).map(
            function (currentElement) {
                return currentElement.address;
            }
        );

        // Create a multisig that will be the service owner
        const setupData = gnosisSafe.interface.encodeFunctionData(
            "setup",
            // signers, threshold, to_address, data, fallback_handler, payment_olas, payment, payment_receiver
            [safeSigners, safeThreshold, AddressZero, "0x", AddressZero, AddressZero, 0, AddressZero]
        );
        let proxyAddress = await safeContracts.calculateProxyAddress(gnosisSafeProxyFactory, gnosisSafe.address,
            setupData, 0);
        await gnosisSafeProxyFactory.createProxyWithNonce(gnosisSafe.address, setupData, 0).then((tx) => tx.wait());

        // Get the multisig
        multisig = await ethers.getContractAt("GnosisSafe", proxyAddress);

        const OLAS = await ethers.getContractFactory("OLAS");
        olas = await OLAS.deploy();
        await olas.deployed();
        // Mint 10 OLAS worth of OLAS olass by default
        await olas.mint(deployer.address, ethers.utils.parseEther("10"));

        // Dispenser address is irrelevant in these tests, so its contract is passed as a zero address
        const VotingEscrow = await ethers.getContractFactory("veOLAS");
        ve = await VotingEscrow.deploy(olas.address, "Voting Escrow OLAS", "veOLAS");
        await ve.deployed();

        const Governor = await ethers.getContractFactory("GovernorOLAS");
        governor = await Governor.deploy(ve.address, timelock.address, initialVotingDelay, initialVotingPeriod,
            initialProposalThreshold, quorum);
        await governor.deployed();

        const GuardCM = await ethers.getContractFactory("GuardCM");
        guard = await GuardCM.deploy(timelock.address, multisig.address, governor.address);
        await guard.deployed();
    });

    context("Timelock manipulation via the CM", async function () {
        it("Enabling CM module as a timelock address ", async function () {
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

        it("CM Guard with a schedule function", async function () {
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

        it("CM Guard with a scheduleBatch function", async function () {
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
            // bytes32(keccak256("unpause")) == 0x3f4ba83a
            const setTargetSelectorsPayload = guard.interface.encodeFunctionData("setTargetSelectors",
                [[treasury.address, treasury.address], ["0x8456cb59", "0x3f4ba83a"], [true, true]]);
            await timelock.execute(guard.address, setTargetSelectorsPayload);

            // Create a payload data for the schedule function
            const payloads = [treasury.interface.encodeFunctionData("pause"),
                treasury.interface.encodeFunctionData("unpause")];

            // Prepare the CM schedule function call
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(timelock, "scheduleBatch", [[treasury.address, treasury.address],
                [0, 0], payloads, Bytes32Zero, Bytes32Zero, 0], nonce, 0, 0);
            for (let i = 0; i < safeThreshold; i++) {
                signMessageData[i] = await safeContracts.safeSignMessage(signers[i+1], multisig, txHashData, 0);
            }
            await safeContracts.executeTx(multisig, txHashData, signMessageData, 0);

            // Execute after the scheduleBatch
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(timelock, "executeBatch", [[treasury.address, treasury.address], payloads], nonce, 0, 0);
            for (let i = 0; i < safeThreshold; i++) {
                signMessageData[i] = await safeContracts.safeSignMessage(signers[i+1], multisig, txHashData, 0);
            }
            await safeContracts.executeTx(multisig, txHashData, signMessageData, 0);

            // Check that the treasury is paused
            const pausedTreasury = await treasury.paused();
            expect(pausedTreasury).to.eq(1);
        });

        it("Pause the CM Guard due to inactive governance", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Setting the CM guard
            let nonce = await multisig.nonce();
            let txHashData = await safeContracts.buildContractCall(multisig, "setGuard", [guard.address], nonce, 0, 0);
            let signMessageData = new Array();
            for (let i = 1; i <= safeThreshold; i++) {
                signMessageData.push(await safeContracts.safeSignMessage(signers[i], multisig, txHashData, 0));
            }
            await safeContracts.executeTx(multisig, txHashData, signMessageData, 0);

            // Lock OLAS for veOLAS
            // Approve signers[0] for 10 OLAS by voting ve
            await olas.approve(ve.address, ethers.utils.parseEther("10"));
            const lockDuration = 4 * 365 * 86400;

            // Lock 10 OLAS, which is enough to cover the 5 OLAS of initial proposal threshold voting power
            await ve.createLock(ethers.utils.parseEther("10"), lockDuration);

            // Setup a proposal to check the governor with the default proposal Id
            const proposalDescription = "Is governance alive?";

            // Propose to check on the governor
            await governor["propose(address[],uint256[],bytes[],string)"]([AddressZero], [0], ["0x"], proposalDescription);
            // Get the proposalId
            const descriptionHash = ethers.utils.id(proposalDescription);
            const proposalId = await governor.hashProposal([AddressZero], [0], ["0x"], descriptionHash);

            // Check that the proposal Ids match
            const defaultProposalId = await guard.governorCheckProposalId();
            expect(proposalId).to.equal(defaultProposalId);

            // Wait until the proposal gets defeated
            await helpers.mine(initialVotingDelay + initialVotingPeriod + 1);

            // Now the proposal must be defeated and the CM can pause the guard
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(guard, "pause", [], nonce, 0, 0);
            for (let i = 0; i < safeThreshold; i++) {
                signMessageData[i] = await safeContracts.safeSignMessage(signers[i+1], multisig, txHashData, 0);
            }
            await safeContracts.executeTx(multisig, txHashData, signMessageData, 0);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });
    });
});
