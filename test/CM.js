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
    const Bytes4Zero = "0x" + "0".repeat(8);
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

    context("Initialization", async function () {
        it("Change governor", async function () {
            // Try to change governor not by the timelock
            await expect(
                guard.changeGovernor(governor.address)
            ).to.be.revertedWithCustomError(guard, "OwnerOnly");

            // Try to change governor to the zero address
            let payload = guard.interface.encodeFunctionData("changeGovernor", [AddressZero]);
            await expect(
                timelock.execute(guard.address, payload)
            ).to.be.reverted;

            payload = guard.interface.encodeFunctionData("changeGovernor", [timelock.address]);
            await timelock.execute(guard.address, payload);
            expect(await guard.owner()).to.equal(timelock.address);
        });

        it("Change governor check proposal Id", async function () {
            // Try to change the proposal Id not by the timelock
            await expect(
                guard.changeGovernorCheckProposalId(5)
            ).to.be.revertedWithCustomError(guard, "OwnerOnly");

            // Try to change proposal Id to the zero address
            let payload = guard.interface.encodeFunctionData("changeGovernorCheckProposalId", [0]);
            await expect(
                timelock.execute(guard.address, payload)
            ).to.be.reverted;

            payload = guard.interface.encodeFunctionData("changeGovernorCheckProposalId", [5]);
            await timelock.execute(guard.address, payload);
            expect(await guard.governorCheckProposalId()).to.equal(5);
        });

        it("Set target selectors", async function () {
            // Try to set selectors not by the timelock
            await expect(
                guard.setTargetSelectors([AddressZero], [Bytes4Zero], [true])
            ).to.be.revertedWithCustomError(guard, "OwnerOnly");

            // Try to set targets with wrong arrays
            let setTargetSelectorsPayload = guard.interface.encodeFunctionData("setTargetSelectors",
                [[AddressZero], [Bytes4Zero, Bytes4Zero], [true]]);
            await expect(
                timelock.execute(guard.address, setTargetSelectorsPayload)
            ).to.be.reverted;

            setTargetSelectorsPayload = guard.interface.encodeFunctionData("setTargetSelectors",
                [[AddressZero], [Bytes4Zero], [true, true]]);
            await expect(
                timelock.execute(guard.address, setTargetSelectorsPayload)
            ).to.be.reverted;
        });

        it("Pause the guard", async function () {
            // Try to pause the guard not by the timelock or the multisig
            await expect(
                guard.pause()
            ).to.be.revertedWithCustomError(guard, "ManagerOnly");

            // Pause the guard by the timelock
            const payload = guard.interface.encodeFunctionData("pause", []);
            await timelock.execute(guard.address, payload);
            expect(await guard.paused()).to.equal(2);
        });
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

            // Setting the CM guard to make sure the module can still act on a multisig
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(multisig, "setGuard", [guard.address], nonce, 0, 0);
            signMessageData = new Array();
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
            let payload = treasury.interface.encodeFunctionData("pause");

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
            let pausedTreasury = await treasury.paused();
            expect(pausedTreasury).to.eq(2);

            // Pause the guard and be able to unpause the treasury even though it's not authorized
            payload = guard.interface.encodeFunctionData("pause", []);
            await timelock.execute(guard.address, payload);

            payload = treasury.interface.encodeFunctionData("unpause");
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(timelock, "schedule", [treasury.address, 0, payload,
                Bytes32Zero, Bytes32Zero, 0], nonce, 0, 0);
            for (let i = 0; i < safeThreshold; i++) {
                signMessageData[i] = await safeContracts.safeSignMessage(signers[i+1], multisig, txHashData, 0);
            }
            await safeContracts.executeTx(multisig, txHashData, signMessageData, 0);

            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(timelock, "execute", [treasury.address, payload], nonce, 0, 0);
            for (let i = 0; i < safeThreshold; i++) {
                signMessageData[i] = await safeContracts.safeSignMessage(signers[i+1], multisig, txHashData, 0);
            }
            await safeContracts.executeTx(multisig, txHashData, signMessageData, 0);

            pausedTreasury = await treasury.paused();
            expect(pausedTreasury).to.eq(1);

            // Unpause the guard
            payload = guard.interface.encodeFunctionData("unpause", []);
            await timelock.execute(guard.address, payload);

            // Negative checks
            // Try to call non-authorized selectors
            payload = treasury.interface.encodeFunctionData("unpause");
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(timelock, "schedule", [treasury.address, 0, payload,
                Bytes32Zero, Bytes32Zero, 0], nonce, 0, 0);
            for (let i = 0; i < safeThreshold; i++) {
                signMessageData[i] = await safeContracts.safeSignMessage(signers[i+1], multisig, txHashData, 0);
            }
            await expect(
                safeContracts.executeTx(multisig, txHashData, signMessageData, 0)
            ).to.be.reverted;

            // Try to do a delegatecall with the authorized selector
            payload = treasury.interface.encodeFunctionData("pause");
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(timelock, "schedule", [treasury.address, 0, payload,
                Bytes32Zero, Bytes32Zero, 0], nonce, 1, 0);
            for (let i = 0; i < safeThreshold; i++) {
                signMessageData[i] = await safeContracts.safeSignMessage(signers[i+1], multisig, txHashData, 0);
            }
            await expect(
                safeContracts.executeTx(multisig, txHashData, signMessageData, 0)
            ).to.be.reverted;

            // Try to pass the payload shorter than at least 4 bytes
            nonce = await multisig.nonce();
            txHashData.data = "0x00";
            txHashData.operation = 0;
            for (let i = 0; i < safeThreshold; i++) {
                signMessageData[i] = await safeContracts.safeSignMessage(signers[i+1], multisig, txHashData, 0);
            }
            await expect(
                safeContracts.executeTx(multisig, txHashData, signMessageData, 0)
            ).to.be.reverted;

            // Try to have a call to the multisig itself
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(multisig, "getThreshold", [], nonce, 0, 0);
            for (let i = 0; i < safeThreshold; i++) {
                signMessageData[i] = await safeContracts.safeSignMessage(signers[i+1], multisig, txHashData, 0);
            }
            await expect(
                safeContracts.executeTx(multisig, txHashData, signMessageData, 0)
            ).to.be.reverted;
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

            // Construct the pausing tx
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(guard, "pause", [], nonce, 0, 0);
            for (let i = 0; i < safeThreshold; i++) {
                signMessageData[i] = await safeContracts.safeSignMessage(signers[i+1], multisig, txHashData, 0);
            }

            // Try to pause the guard when the proposal is not yet defeated
            await expect(
                safeContracts.executeTx(multisig, txHashData, signMessageData, 0)
            ).to.be.reverted;

            // Wait until the proposal gets defeated
            await helpers.mine(initialVotingDelay + initialVotingPeriod + 1);

            // Now the proposal must be defeated and the CM can pause the guard
            await safeContracts.executeTx(multisig, txHashData, signMessageData, 0);

            // Try to unpause the guard by a non-owner
            await expect(
                guard.connect(deployer).unpause()
            ).to.be.revertedWithCustomError(guard, "OwnerOnly");

            // The timelock now can unpause the guard
            const unpausePayload = guard.interface.encodeFunctionData("unpause");
            await timelock.execute(guard.address, unpausePayload);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });
    });
});
