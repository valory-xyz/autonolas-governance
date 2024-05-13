/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Governance OLAS on wveOLAS", function () {
    let gnosisSafeL2;
    let gnosisSafeProxyFactory;
    let token;
    let ve;
    let wve;
    let signers;
    const oneWeek = 7 * 86400;
    const oneOLASBalance = ethers.utils.parseEther("1");
    const twoOLASBalance = ethers.utils.parseEther("2");
    const fiveOLASBalance = ethers.utils.parseEther("5");
    const tenOLASBalance = ethers.utils.parseEther("10");
    const AddressZero = "0x" + "0".repeat(40);
    const bytes32Zero = "0x" + "0".repeat(64);
    const safeThreshold = 7;
    const nonce =  0;
    const minDelay = 1; // blocks
    const initialVotingDelay = 0; // blocks
    const initialVotingPeriod = 1; // blocks
    const initialProposalThreshold = fiveOLASBalance; // required voting power
    const quorum = 1; // quorum factor
    const proposalDescription = "Proposal 0";
    beforeEach(async function () {
        const GnosisSafeL2 = await ethers.getContractFactory("GnosisSafeL2");
        gnosisSafeL2 = await GnosisSafeL2.deploy();
        await gnosisSafeL2.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        const Token = await ethers.getContractFactory("OLAS");
        token = await Token.deploy();
        await token.deployed();

        const VotingEscrow = await ethers.getContractFactory("veOLAS");
        ve = await VotingEscrow.deploy(token.address, "Voting Escrow OLAS", "veOLAS");
        await ve.deployed();

        const wVotingEscrow = await ethers.getContractFactory("wveOLAS");
        wve = await wVotingEscrow.deploy(ve.address, token.address);
        await wve.deployed();

        signers = await ethers.getSigners();

        // Mint 10 OLAS worth of OLAS tokens by default
        await token.mint(signers[0].address, tenOLASBalance);
        const balance = await token.balanceOf(signers[0].address);
        expect(ethers.utils.formatEther(balance) == 10).to.be.true;
    });

    context("Initialization", async function () {
        it("Governance setup: deploy ve, timelock, governor, drop deployer role", async function () {
            // Deploy Safe multisig
            const safeSigners = signers.slice(1, 10).map(
                function (currentElement) {
                    return currentElement.address;
                }
            );

            const setupData = gnosisSafeL2.interface.encodeFunctionData(
                "setup",
                // signers, threshold, to_address, data, fallback_handler, payment_token, payment, payment_receiver
                [safeSigners, safeThreshold, AddressZero, "0x", AddressZero, AddressZero, 0, AddressZero]
            );

            // Create Safe proxy
            const safeContracts = require("@gnosis.pm/safe-contracts");
            const proxyAddress = await safeContracts.calculateProxyAddress(gnosisSafeProxyFactory, gnosisSafeL2.address,
                setupData, nonce);

            await gnosisSafeProxyFactory.createProxyWithNonce(gnosisSafeL2.address, setupData, nonce).then((tx) => tx.wait());
            // console.log("Safe proxy deployed to", proxyAddress);

            // Deploy Timelock
            const executors = [];
            const proposers = [proxyAddress];
            const Timelock = await ethers.getContractFactory("Timelock");
            const timelock = await Timelock.deploy(minDelay, proposers, executors);
            await timelock.deployed();
            // console.log("Timelock deployed to", timelock.address);

            // Deploy Governance Bravo
            const GovernorBravo = await ethers.getContractFactory("GovernorOLAS");
            const governor = await GovernorBravo.deploy(wve.address, timelock.address, initialVotingDelay,
                initialVotingPeriod, initialProposalThreshold, quorum);
            await governor.deployed();
            // console.log("Governor Bravo deployed to", governor.address);

            // Checks for the compatibility with IERC165
            const interfaceIdIERC165 = "0x01ffc9a7";
            const checkInterfaceId = await governor.supportsInterface(interfaceIdIERC165);
            expect(checkInterfaceId).to.equal(true);

            // Change the admin from deployer to governor
            const deployer = signers[0];
            const adminRole = ethers.utils.id("TIMELOCK_ADMIN_ROLE");
            await timelock.connect(deployer).grantRole(adminRole, governor.address);
            await timelock.connect(deployer).renounceRole(adminRole, deployer.address);
            // Check that the deployer does not have rights anymore
            await expect(
                timelock.connect(deployer).revokeRole(adminRole, governor.address)
            ).to.be.reverted;
        });

        it("Changes the ownership of a governance contract and a timelock", async function () {
            const deployer = signers[0];
            // Approve signers[0] for 10 OLAS by voting ve
            await token.approve(ve.address, tenOLASBalance);
            // Define 4 years for the lock duration in Voting Escrow.
            // This will result in voting power being almost exactly as OLAS amount locked:
            // voting power = amount * t_left_before_unlock / t_max
            const lockDuration = 4 * 365 * 86400;

            // Lock 10 OLAS, which is enough to cover the 5 OLAS of initial proposal threshold voting power
            await ve.createLock(tenOLASBalance, lockDuration);

            // Deploy first timelock
            const executors = [deployer.address];
            const proposers = [deployer.address];
            const Timelock = await ethers.getContractFactory("Timelock");
            const timelock = await Timelock.deploy(minDelay, proposers, executors);
            await timelock.deployed();

            const timelock2 = await Timelock.deploy(minDelay, proposers, executors);
            await timelock2.deployed();

            // Deploy Governance Bravo with a deployer being a timelock address
            const GovernorBravo = await ethers.getContractFactory("GovernorOLAS");
            const governor = await GovernorBravo.deploy(wve.address, timelock.address, initialVotingDelay,
                initialVotingPeriod, initialProposalThreshold, quorum);
            await governor.deployed();

            // Check the initial timelock address
            expect(await governor.timelock()).to.equal(timelock.address);

            // Grand governor proposer and executor roles in the timelock
            const proposerRole = ethers.utils.id("PROPOSER_ROLE");
            await timelock.grantRole(proposerRole, governor.address);
            const executorRole = ethers.utils.id("EXECUTOR_ROLE");
            await timelock.grantRole(executorRole, governor.address);

            // Update timelock to a different address: possible via governor execute function
            // The action from timelock itself without the governance proposal will fail as it tries to match
            // the execution request in the msg.value coming to the governor, and straight call to the function is rejecte.
            await expect(
                governor.updateTimelock(timelock2.address)
            ).to.be.revertedWith("Governor: onlyGovernance");

            // Let the deployer propose the change of the timelock
            let callData = governor.interface.encodeFunctionData("updateTimelock", [timelock2.address]);
            await governor["propose(address[],uint256[],bytes[],string)"]([governor.address], [0],
                [callData], proposalDescription);

            // Get the proposalId
            const descriptionHash = ethers.utils.id(proposalDescription);
            const proposalId = await governor.hashProposal([governor.address], [0], [callData],
                descriptionHash);

            // If initialVotingDelay is greater than 0 we have to wait that many blocks before the voting starts
            // Casting votes for the proposalId: 0 - Against, 1 - For, 2 - Abstain
            await governor.castVote(proposalId, 1);
            await governor["queue(address[],uint256[],bytes[],bytes32)"]([governor.address], [0],
                [callData], descriptionHash);

            // Waiting for the minDelay number of blocks to pass
            for (let i = 0; i < minDelay; i++) {
                ethers.provider.send("evm_mine");
            }

            // Execute the proposed operation and check the execution result
            await governor["execute(uint256)"](proposalId);

            // Check the new timelock address
            expect(await governor.timelock()).to.equal(timelock2.address);


            // Trying to change back timelock with just the proposal roles
            callData = governor.interface.encodeFunctionData("updateTimelock", [timelock.address]);
            // Schedule the change right away by the deployer as a proposer
            await timelock2.schedule(governor.address, 0, callData, bytes32Zero, bytes32Zero, minDelay);

            // Waiting for the minDelay number of blocks to pass
            for (let i = 0; i < minDelay; i++) {
                ethers.provider.send("evm_mine");
            }

            // Executing via this rpoposal will fail as onlyGovernance checks for the proposals passed throught the
            // governor itself, i.e with voting
            await expect(
                timelock2.execute(governor.address, 0, callData, bytes32Zero, bytes32Zero)
            ).to.be.revertedWith("TimelockController: underlying transaction reverted");
        });

        it("Cancel the proposal that was setup via delegator proposal", async function () {
            const deployer = signers[0];
            const balance = await token.balanceOf(deployer.address);
            expect(ethers.utils.formatEther(balance) == 10).to.be.true;

            // Approve signers[0] for 10 OLA by voting ve
            await token.connect(deployer).approve(ve.address, tenOLASBalance);

            // Define 4 years for the lock duration.
            // This will result in voting power being almost exactly as OLA amount locked:
            // voting power = amount * t_left_before_unlock / t_max
            const fourYears = 4 * 365 * 86400;
            const lockDuration = fourYears;

            // Lock 5 OLA, which is lower than the initial proposal threshold by a bit
            await ve.connect(deployer).createLock(fiveOLASBalance, lockDuration);
            // Add a bit more
            await ve.connect(deployer).increaseAmount(oneOLASBalance);

            // Deploy Timelock
            const executors = [];
            const proposers = [];
            const Timelock = await ethers.getContractFactory("Timelock");
            const timelock = await Timelock.deploy(minDelay, proposers, executors);
            await timelock.deployed();

            // Deploy Governance Bravo
            const GovernorBravo = await ethers.getContractFactory("GovernorOLAS");
            const governor = await GovernorBravo.deploy(wve.address, timelock.address, initialVotingDelay,
                initialVotingPeriod, initialProposalThreshold, quorum);
            await governor.deployed();

            // Grand governor an admin, proposer, executor and canceller role in the timelock
            const adminRole = ethers.utils.id("TIMELOCK_ADMIN_ROLE");
            await timelock.grantRole(adminRole, governor.address);
            const proposerRole = ethers.utils.id("PROPOSER_ROLE");
            await timelock.grantRole(proposerRole, governor.address);
            const executorRole = ethers.utils.id("EXECUTOR_ROLE");
            await timelock.grantRole(executorRole, governor.address);
            const cancellerRole = ethers.utils.id("CANCELLER_ROLE");
            await timelock.grantRole(cancellerRole, governor.address);

            // Schedule an operation from timelock via a proposer (deployer by default)
            const callData = "0x";
            // Solidity overridden functions must be explicitly declared
            // https://github.com/ethers-io/ethers.js/issues/407
            await governor["propose(address[],uint256[],bytes[],string)"]([AddressZero], [0],
                [callData], proposalDescription);

            // Get the proposalId
            const descriptionHash = ethers.utils.id(proposalDescription);
            const proposalId = await governor.hashProposal([AddressZero], [0], [callData],
                descriptionHash);

            // If initialVotingDelay is greater than 0 we have to wait that many blocks before the voting starts
            // Casting votes for the proposalId: 0 - Against, 1 - For, 2 - Abstain
            await governor.castVote(proposalId, 1);
            await governor["queue(address[],uint256[],bytes[],bytes32)"]([AddressZero], [0],
                [callData], descriptionHash);

            // Cancel the proposal
            await governor["cancel(uint256)"](proposalId);

            // Check that the proposal was cancelled: enum value of ProposalState.Canceled == 2
            const proposalState = await governor.state(proposalId);
            expect(proposalState).to.equal(2);
        });

        it("Deposit for voting power: deposit 10 OLAS worth of ve to address 1", async function () {
            // Get the list of delegators and a delegatee address
            const numDelegators = 10;
            const delegatee = signers[1].address;

            // Transfer initial balances to all the gelegators: 1 OLAS to each
            for (let i = 1; i <= numDelegators; i++) {
                await token.transfer(signers[i].address, oneOLASBalance);
                const balance = await token.balanceOf(signers[i].address);
                expect(ethers.utils.formatEther(balance) == 1).to.be.true;
            }

            // Approve signers[1]-signers[10] for 1 OLAS by voting ve
            for (let i = 1; i <= numDelegators; i++) {
                await token.connect(signers[i]).approve(ve.address, oneOLASBalance);
            }

            // Define 1 week for the lock duration
            const lockDuration = oneWeek;

            // Deposit tokens as a voting power to a chosen delegatee
            await ve.connect(signers[1]).createLock(oneOLASBalance, lockDuration);
            for (let i = 2; i <= numDelegators; i++) {
                await ve.connect(signers[i]).depositFor(delegatee, oneOLASBalance);
            }

            // Given 1 OLAS worth of voting power from every address, the cumulative voting power must be 10
            const vPower = await ve.getVotes(delegatee);
            expect(ethers.utils.formatEther(vPower) > 0).to.be.true;

            // The rest of addresses must have zero voting power
            for (let i = 2; i <= numDelegators; i++) {
                expect(await ve.getVotes(signers[i].address)).to.be.equal(0);
            }
        });

        it("Should fail to propose if voting power is not enough for proposalThreshold", async function () {
            const balance = await token.balanceOf(signers[0].address);
            expect(ethers.utils.formatEther(balance) == 10).to.be.true;

            // Approve signers[0] for 10 OLAS by voting ve
            await token.connect(signers[0]).approve(ve.address, tenOLASBalance);

            // Define 4 years for the lock duration.
            // This will result in voting power being almost exactly as OLAS amount locked:
            // voting power = amount * t_left_before_unlock / t_max
            const fourYears = 4 * 365 * oneWeek / 7;
            const lockDuration = fourYears;

            // Lock 5 OLAS, which is lower than the initial proposal threshold by a bit
            await ve.connect(signers[0]).createLock(fiveOLASBalance, lockDuration);

            // Deploy simple version of a timelock
            const executors = [];
            const proposers = [];
            const Timelock = await ethers.getContractFactory("Timelock");
            const timelock = await Timelock.deploy(minDelay, proposers, executors);
            await timelock.deployed();

            // Deploy Governance Bravo
            const GovernorBravo = await ethers.getContractFactory("GovernorOLAS");
            const governor = await GovernorBravo.deploy(wve.address, timelock.address, initialVotingDelay,
                initialVotingPeriod, initialProposalThreshold, quorum);
            await governor.deployed();

            // Initial proposal threshold is 10 OLAS, our delegatee voting power is almost 5 OLAS
            await expect(
                // Solidity overridden functions must be explicitly declared
                governor.connect(signers[0])["propose(address[],uint256[],bytes[],string)"]([AddressZero], [0],
                    ["0x"], proposalDescription)
            ).to.be.revertedWith("Governor: proposer votes below proposal threshold");

            // Adding voting power, and the proposal must go through, 4 + 2 of OLAS in voting power is almost 6 > 5 required
            await ve.connect(signers[0]).increaseAmount(twoOLASBalance);
            await governor.connect(signers[0])["propose(address[],uint256[],bytes[],string)"]([AddressZero], [0],
                ["0x"], proposalDescription);
        });

        it("Cancel the proposal that was setup via regular governance proposal", async function () {
            const deployer = signers[0];
            const balance = await token.balanceOf(deployer.address);
            expect(ethers.utils.formatEther(balance) == 10).to.be.true;

            // Approve signers[0] for 10 OLA by voting ve
            await token.connect(deployer).approve(ve.address, tenOLASBalance);

            // Define 4 years for the lock duration.
            // This will result in voting power being almost exactly as OLA amount locked:
            // voting power = amount * t_left_before_unlock / t_max
            const fourYears = 4 * 365 * 86400;
            const lockDuration = fourYears;

            // Lock 5 OLA, which is lower than the initial proposal threshold by a bit
            await ve.connect(deployer).createLock(fiveOLASBalance, lockDuration);
            // Add a bit more
            await ve.connect(deployer).increaseAmount(oneOLASBalance);

            // Deploy Timelock
            const proposers = [deployer.address];
            const executors = [deployer.address];
            const Timelock = await ethers.getContractFactory("Timelock");
            const timelock = await Timelock.deploy(minDelay, proposers, executors);
            await timelock.deployed();

            // Deploy Governance Bravo
            const GovernorBravo = await ethers.getContractFactory("GovernorOLAS");
            const governor = await GovernorBravo.deploy(wve.address, timelock.address, initialVotingDelay,
                initialVotingPeriod, initialProposalThreshold, quorum);
            await governor.deployed();

            // Grand governor an admin, proposer, executor and canceller role in the timelock
            const adminRole = ethers.utils.id("TIMELOCK_ADMIN_ROLE");
            await timelock.grantRole(adminRole, governor.address);
            const proposerRole = ethers.utils.id("PROPOSER_ROLE");
            await timelock.grantRole(proposerRole, governor.address);
            const executorRole = ethers.utils.id("EXECUTOR_ROLE");
            await timelock.grantRole(executorRole, governor.address);
            const cancellerRole = ethers.utils.id("CANCELLER_ROLE");
            await timelock.grantRole(cancellerRole, governor.address);

            // Schedule an operation from timelock via a proposer (deployer by default)
            const callData = "0x";
            // Solidity overridden functions must be explicitly declared
            // https://github.com/ethers-io/ethers.js/issues/407
            const proposalTx = await governor["propose(address[],uint256[],bytes[],string)"]([AddressZero], [0],
                [callData], proposalDescription);
            const resultTx = await proposalTx.wait();
            expect(resultTx.events[0].event).to.equal("ProposalCreated");
            // Get the proposal arguments from the event
            const proposalArgs = resultTx.events[0].args;

            // Get the proposalId
            const descriptionHash = ethers.utils.id(proposalDescription);
            const proposalId = await governor.hashProposal([AddressZero], [0], [callData],
                descriptionHash);

            // If initialVotingDelay is greater than 0 we have to wait that many blocks before the voting starts
            // Casting votes for the proposalId: 0 - Against, 1 - For, 2 - Abstain
            await governor.castVote(proposalId, 1);
            await governor["queue(address[],uint256[],bytes[],bytes32)"]([AddressZero], [0],
                [callData], descriptionHash);

            // Cancel the proposal via the timelock
            // We need to encode the exact same data that was coded into the proposal with descriptionHash being the salt
            // It has to correspond to: timelock.hashOperationBatch([AddressZero], [0], [callData], bytes32Zero, descriptionHash);
            const proposalHash = timelock.hashOperationBatch(proposalArgs[2], proposalArgs[3],
                proposalArgs[5], bytes32Zero, ethers.utils.id(proposalArgs[8]));
            await timelock.cancel(proposalHash);

            // Check that the proposal was cancelled: enum value of ProposalState.Canceled == 2
            const proposalState = await governor.state(proposalId);
            expect(proposalState).to.equal(2);
        });
    });
});
