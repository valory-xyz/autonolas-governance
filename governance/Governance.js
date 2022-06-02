/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Governance unit", function () {
    let gnosisSafeL2;
    let gnosisSafeProxyFactory;
    let token;
    let ve;
    let signers;
    const oneWeek = 7 * 86400;
    const oneOLABalance = ethers.utils.parseEther("1");
    const twoOLABalance = ethers.utils.parseEther("2");
    const fiveOLABalance = ethers.utils.parseEther("5");
    const tenOLABalance = ethers.utils.parseEther("10");
    const AddressZero = "0x" + "0".repeat(40);
    const bytes32Zero = "0x" + "0".repeat(64);
    const safeThreshold = 7;
    const nonce =  0;
    const minDelay = 1; // blocks
    const initialVotingDelay = 0; // blocks
    const initialVotingPeriod = 1; // blocks
    const initialProposalThreshold = fiveOLABalance; // required voting power
    const quorum = 1; // quorum factor
    const proposalDescription = "Proposal 0";
    beforeEach(async function () {
        const GnosisSafeL2 = await ethers.getContractFactory("GnosisSafeL2");
        gnosisSafeL2 = await GnosisSafeL2.deploy();
        await gnosisSafeL2.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        const Token = await ethers.getContractFactory("OLA");
        token = await Token.deploy(0);
        await token.deployed();

        // Dispenser address is irrelevant in these tests, so its contract is passed as a zero address
        const VotingEscrow = await ethers.getContractFactory("VotingEscrow");
        ve = await VotingEscrow.deploy(token.address, "Voting Escrow OLA", "veOLA");
        await ve.deployed();

        signers = await ethers.getSigners();

        // Mint 10 OLA worth of OLA tokens by default
        await token.mint(signers[0].address, tenOLABalance);
        const balance = await token.balanceOf(signers[0].address);
        expect(ethers.utils.formatEther(balance) == 10).to.be.true;
    });

    context("Initialization", async function () {
        it("Governance setup: deploy ve, timelock, governorBravo, drop deployer role", async function () {
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
            const GovernorBravo = await ethers.getContractFactory("GovernorOLA");
            const governorBravo = await GovernorBravo.deploy(ve.address, timelock.address, initialVotingDelay,
                initialVotingPeriod, initialProposalThreshold, quorum);
            await governorBravo.deployed();
            // console.log("Governor Bravo deployed to", governorBravo.address);

            // Checks for the compatibility with IERC165
            const interfaceIdIERC165 = "0x01ffc9a7";
            const checkInterfaceId = await governorBravo.supportsInterface(interfaceIdIERC165);
            expect(checkInterfaceId).to.equal(true);

            // Change the admin from deployer to governorBravo
            const deployer = signers[0];
            const adminRole = ethers.utils.id("TIMELOCK_ADMIN_ROLE");
            await timelock.connect(deployer).grantRole(adminRole, governorBravo.address);
            await timelock.connect(deployer).renounceRole(adminRole, deployer.address);
            // Check that the deployer does not have rights anymore
            await expect(
                timelock.connect(deployer).revokeRole(adminRole, governorBravo.address)
            ).to.be.revertedWith("AccessControl: account ");
        });

        it("Changes the ownership of a governance contract and a timelock", async function () {
            const deployer = signers[0];
            // Approve signers[0] for 10 OLA by voting ve
            await token.approve(ve.address, tenOLABalance);
            // Define 4 years for the lock duration in Voting Escrow.
            // This will result in voting power being almost exactly as OLA amount locked:
            // voting power = amount * t_left_before_unlock / t_max
            const lockDuration = 4 * 365 * 86400;

            // Lock 10 OLA, which is enough to cover the 5 OLA of initial proposal threshold voting power
            await ve.createLock(tenOLABalance, lockDuration);

            // Deploy first timelock
            const executors = [deployer.address];
            const proposers = [deployer.address];
            const Timelock = await ethers.getContractFactory("Timelock");
            const timelock = await Timelock.deploy(minDelay, proposers, executors);
            await timelock.deployed();

            const timelock2 = await Timelock.deploy(minDelay, proposers, executors);
            await timelock2.deployed();

            // Deploy Governance Bravo with a deployer being a timelock address
            const GovernorBravo = await ethers.getContractFactory("GovernorOLA");
            const governorBravo = await GovernorBravo.deploy(ve.address, timelock.address, initialVotingDelay,
                initialVotingPeriod, initialProposalThreshold, quorum);
            await governorBravo.deployed();

            // Check the initial timelock address
            expect(await governorBravo.timelock()).to.equal(timelock.address);

            // Grand governorBravo proposer and executor roles in the timelock
            const proposerRole = ethers.utils.id("PROPOSER_ROLE");
            await timelock.grantRole(proposerRole, governorBravo.address);
            const executorRole = ethers.utils.id("EXECUTOR_ROLE");
            await timelock.grantRole(executorRole, governorBravo.address);

            // Update timelock to a different address: possible via governor execute function
            // The action from timelock itself without the governance proposal will fail as it tries to match
            // the execution request in the msg.value coming to the governor, and straight call to the function is rejecte.
            await expect(
                governorBravo.updateTimelock(timelock2.address)
            ).to.be.revertedWith("Governor: onlyGovernance");

            // Let the deployer propose the change of the timelock
            let callData = governorBravo.interface.encodeFunctionData("updateTimelock", [timelock2.address]);
            await governorBravo["propose(address[],uint256[],bytes[],string)"]([governorBravo.address], [0],
                [callData], proposalDescription);

            // Get the proposalId
            const descriptionHash = ethers.utils.id(proposalDescription);
            const proposalId = await governorBravo.hashProposal([governorBravo.address], [0], [callData],
                descriptionHash);

            // If initialVotingDelay is greater than 0 we have to wait that many blocks before the voting starts
            // Casting votes for the proposalId: 0 - Against, 1 - For, 2 - Abstain
            await governorBravo.castVote(proposalId, 1);
            await governorBravo["queue(address[],uint256[],bytes[],bytes32)"]([governorBravo.address], [0],
                [callData], descriptionHash);

            // Waiting for the minDelay number of blocks to pass
            for (let i = 0; i < minDelay; i++) {
                ethers.provider.send("evm_mine");
            }

            // Execute the proposed operation and check the execution result
            await governorBravo["execute(uint256)"](proposalId);

            // Check the new timelock address
            expect(await governorBravo.timelock()).to.equal(timelock2.address);


            // Trying to change back timelock with just the proposal roles
            callData = governorBravo.interface.encodeFunctionData("updateTimelock", [timelock.address]);
            // Schedule the change right away by the deployer as a proposer
            await timelock2.schedule(governorBravo.address, 0, callData, bytes32Zero, bytes32Zero, minDelay);

            // Waiting for the minDelay number of blocks to pass
            for (let i = 0; i < minDelay; i++) {
                ethers.provider.send("evm_mine");
            }

            // Executing via this rpoposal will fail as onlyGovernance checks for the proposals passed throught the
            // governor itself, i.e with voting
            await expect(
                timelock2.execute(governorBravo.address, 0, callData, bytes32Zero, bytes32Zero)
            ).to.be.revertedWith("TimelockController: underlying transaction reverted");
        });

        it("Deposit for voting power: deposit 10 OLA worth of ve to address 1", async function () {
            // Get the list of delegators and a delegatee address
            const numDelegators = 10;
            const delegatee = signers[1].address;

            // Transfer initial balances to all the gelegators: 1 OLA to each
            for (let i = 1; i <= numDelegators; i++) {
                await token.transfer(signers[i].address, oneOLABalance);
                const balance = await token.balanceOf(signers[i].address);
                expect(ethers.utils.formatEther(balance) == 1).to.be.true;
            }

            // Approve signers[1]-signers[10] for 1 OLA by voting ve
            for (let i = 1; i <= numDelegators; i++) {
                await token.connect(signers[i]).approve(ve.address, oneOLABalance);
            }

            // Define 1 week for the lock duration
            const lockDuration = oneWeek;

            // Deposit tokens as a voting power to a chosen delegatee
            await ve.connect(signers[1]).createLock(oneOLABalance, lockDuration);
            for (let i = 2; i <= numDelegators; i++) {
                await ve.connect(signers[i]).depositFor(delegatee, oneOLABalance);
            }

            // Given 1 OLA worth of voting power from every address, the cumulative voting power must be 10
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

            // Approve signers[0] for 10 OLA by voting ve
            await token.connect(signers[0]).approve(ve.address, tenOLABalance);

            // Define 4 years for the lock duration.
            // This will result in voting power being almost exactly as OLA amount locked:
            // voting power = amount * t_left_before_unlock / t_max
            const fourYears = 4 * 365 * oneWeek / 7;
            const lockDuration = fourYears;

            // Lock 5 OLA, which is lower than the initial proposal threshold by a bit
            await ve.connect(signers[0]).createLock(fiveOLABalance, lockDuration);

            // Deploy simple version of a timelock
            const executors = [];
            const proposers = [];
            const Timelock = await ethers.getContractFactory("Timelock");
            const timelock = await Timelock.deploy(minDelay, proposers, executors);
            await timelock.deployed();

            // Deploy Governance Bravo
            const GovernorBravo = await ethers.getContractFactory("GovernorOLA");
            const governorBravo = await GovernorBravo.deploy(ve.address, timelock.address, initialVotingDelay,
                initialVotingPeriod, initialProposalThreshold, quorum);
            await governorBravo.deployed();

            // Initial proposal threshold is 10 OLA, our delegatee voting power is almost 5 OLA
            await expect(
                // Solidity overridden functions must be explicitly declared
                governorBravo.connect(signers[0])["propose(address[],uint256[],bytes[],string)"]([AddressZero], [0],
                    ["0x"], proposalDescription)
            ).to.be.revertedWith("Governor: proposer votes below proposal threshold");

            // Adding voting power, and the proposal must go through, 4 + 2 of OLA in voting power is almost 6 > 5 required
            await ve.connect(signers[0]).increaseAmount(twoOLABalance);
            await governorBravo.connect(signers[0])["propose(address[],uint256[],bytes[],string)"]([AddressZero], [0],
                ["0x"], proposalDescription);
        });
    });
});
