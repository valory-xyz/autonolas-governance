/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("Vote Weighting veOLAS", function () {
    let olas;
    let ve;
    let vw;
    let signers;
    let deployer;
    const initialMint = "1000000000000000000000000"; // 1_000_000
    const oneWeek = 7 * 86400;
    const oneYear = 365 * 86400;
    const chainId = 1;
    const maxVoteWeight = 10000;
    const E18 = 10**18;
    const oneOLASBalance = ethers.utils.parseEther("1");
    const AddressZero = ethers.constants.AddressZero;
    const HashZero = ethers.constants.HashZero;

    function getNextTime(ts) {
        return Math.floor((ts + oneWeek) / oneWeek) * oneWeek;
    }

    function convertAddressToBytes32(account) {
        return ("0x" + "0".repeat(24) + account.slice(2)).toLowerCase();
    }

    function convertBytes32ToAddress(account) {
        return "0x" + account.slice(26);
    }

    beforeEach(async function () {
        const OLAS = await ethers.getContractFactory("OLAS");
        olas = await OLAS.deploy();
        await olas.deployed();

        signers = await ethers.getSigners();
        deployer = signers[0];
        await olas.mint(deployer.address, initialMint);

        const VE = await ethers.getContractFactory("veOLAS");
        ve = await VE.deploy(olas.address, "Voting Escrow OLAS", "veOLAS");
        await ve.deployed();

        const VoteWeighting = await ethers.getContractFactory("VoteWeighting");
        vw = await VoteWeighting.deploy(ve.address);
        await vw.deployed();
    });

    context("Initialization", async function () {
        it("Should fail when deploying with the zero address", async function () {
            const VoteWeighting = await ethers.getContractFactory("VoteWeighting");
            await expect(
                VoteWeighting.deploy(AddressZero)
            ).to.be.revertedWithCustomError(vw, "ZeroAddress");
        });

        it("veOLAS", async function () {
            // Checks for the veOLAS account
            const veAddress = await vw.ve();
            expect(ve.address).to.equal(veAddress);
        });
        
        it("Changing owner", async function () {
            const account = signers[1];

            // Trying to change owner from a non-owner account address
            await expect(
                vw.connect(account).changeOwner(account.address)
            ).to.be.revertedWithCustomError(vw, "OwnerOnly");

            // Trying to change owner for the zero address
            await expect(
                vw.connect(deployer).changeOwner(AddressZero)
            ).to.be.revertedWithCustomError(vw, "ZeroAddress");

            // Changing the owner
            await vw.connect(deployer).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                vw.connect(deployer).changeOwner(deployer.address)
            ).to.be.revertedWithCustomError(vw, "OwnerOnly");
        });

        it("Setting dispenser", async function () {
            // Try to set not by the owner
            await expect(
                vw.connect(signers[1]).changeDispenser(deployer.address)
            ).to.be.revertedWithCustomError(vw, "OwnerOnly");

            // Set dispenser to any address
            await vw.changeDispenser(deployer.address);

            // Zero address
            await vw.changeDispenser(AddressZero);
        });
    });

    context("Adding nominees", async function () {
        it("Should fail with wrong nominee params", async function () {
            let nominee = signers[1].address;
            // Lock one OLAS into veOLAS
            await olas.approve(ve.address, oneOLASBalance);
            await ve.createLock(oneOLASBalance, oneYear);

            // Try to add a zero address nominee
            await expect(
                vw.addNomineeEVM(AddressZero, chainId)
            ).to.be.revertedWithCustomError(vw, "ZeroAddress");

            // Try to add a zero chain Id
            await expect(
                vw.addNomineeEVM(nominee, 0)
            ).to.be.revertedWithCustomError(vw, "ZeroValue");

            // Try to add an overflow chain Id
            const maxEVMChainId = await vw.MAX_EVM_CHAIN_ID();
            const overflowChainId = maxEVMChainId.add(1);
            await expect(
                vw.addNomineeEVM(nominee, overflowChainId)
            ).to.be.revertedWithCustomError(vw, "Overflow");

            // Try to add an underflow chain Id for the non-EVM chain
            nominee = convertAddressToBytes32(nominee);
            await expect(
                vw.addNomineeNonEVM(nominee, maxEVMChainId)
            ).to.be.revertedWithCustomError(vw, "Underflow");

            // Try to add a non-EVM nominee with a zero address
            await expect(
                vw.addNomineeNonEVM(HashZero, chainId)
            ).to.be.revertedWithCustomError(vw, "ZeroAddress");
        });

        it("Add nominee", async function () {
            let nominee = signers[1].address;
            // Lock one OLAS into veOLAS
            await olas.approve(ve.address, oneOLASBalance);
            await ve.createLock(oneOLASBalance, oneYear);

            // Add a nominee
            await vw.addNomineeEVM(nominee, chainId);

            // Try to add the same nominee
            await expect(
                vw.addNomineeEVM(nominee, chainId)
            ).to.be.revertedWithCustomError(vw, "NomineeAlreadyExists");

            // Check the nominee setup
            const numNominees = await vw.getNumNominees();
            expect(numNominees).to.equal(1);
            const allNominees = await vw.getAllNominees();
            expect(allNominees.length).to.equal(numNominees.add(1));

            const nomineeChainId = await vw.getNominee(1);
            expect(nomineeChainId.account).to.equal(convertAddressToBytes32(nominee));
            expect(nomineeChainId.chainId).to.equal(chainId);

            let nomineeId = await vw.getNomineeId(convertAddressToBytes32(nominee), chainId);
            expect(nomineeId).to.equal(1);

            // Check the nominee Id of a nonexistent nominee
            nomineeId = await vw.getNomineeId(convertAddressToBytes32(nominee), chainId + 1);
            expect(nomineeId).to.equal(0);

            // Adding a non-EVM nominee
            nominee = convertAddressToBytes32(nominee);
            const maxEVMChainId = await vw.MAX_EVM_CHAIN_ID();
            await vw.addNomineeNonEVM(nominee, maxEVMChainId.add(1));
        });

        it("Get nominees", async function () {
            const nominee = signers[1].address;
            // Add a nominee
            await vw.addNomineeEVM(nominee, chainId);

            // Try to get the zero-th nominees
            await expect(
                vw.getNominee(0)
            ).to.be.revertedWithCustomError(vw, "ZeroValue");
            await expect(
                vw.getRemovedNominee(0)
            ).to.be.revertedWithCustomError(vw, "ZeroValue");

            // Try to get the nonexistent nominee
            await expect(
                vw.getNominee(2)
            ).to.be.revertedWithCustomError(vw, "Overflow");
            await expect(
                vw.getRemovedNominee(1)
            ).to.be.revertedWithCustomError(vw, "Overflow");

            // Add one more nominee
            await vw.addNomineeEVM(nominee, chainId + 1);
            // Try to get the nonexistent nominee
            await expect(
                vw.getNominee(3)
            ).to.be.revertedWithCustomError(vw, "Overflow");
        });
    });

    context("Voting", async function () {
        it("Should fail with wrong input arguments", async function () {
            // Add a nominee
            let nominee = signers[1].address;
            await vw.addNomineeEVM(nominee, chainId);
            nominee = convertAddressToBytes32(nominee);

            // Approve OLAS for veOLAS
            await olas.approve(ve.address, oneOLASBalance);

            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Lock one OLAS into veOLAS for one week
            await ve.createLock(oneOLASBalance, oneWeek);

            // Try to vote for the nominee when the lock is about to expire
            await expect(
                vw.voteForNomineeWeights(nominee, chainId, maxVoteWeight)
            ).to.be.revertedWithCustomError(vw, "LockExpired");

            // Restore to the state of the snapshot
            await snapshot.restore();

            // Lock one OLAS into veOLAS for one year
            await ve.createLock(oneOLASBalance, oneYear);

            // Try to vote for the nominee with the bigger weight
            await expect(
                vw.voteForNomineeWeights(nominee, chainId, maxVoteWeight + 1)
            ).to.be.revertedWithCustomError(vw, "Overflow");

            // Vote for the nominee
            await vw.voteForNomineeWeights(nominee, chainId, maxVoteWeight);

            // Try to vote for the same nominee again within a defined period
            await expect(
                vw.voteForNomineeWeights(nominee, chainId, maxVoteWeight)
            ).to.be.revertedWithCustomError(vw, "VoteTooOften");

            // Try to vote for another nominee with all the voting power used
            nominee = signers[2].address;
            await vw.addNomineeEVM(nominee, chainId);
            nominee = convertAddressToBytes32(nominee);

            await expect(
                vw.voteForNomineeWeights(nominee, chainId, 1)
            ).to.be.revertedWithCustomError(vw, "Overflow");

            // Voting with the zero power is possible
            await vw.voteForNomineeWeights(nominee, chainId, 0);

            // Try to checkpoint nominee that does not exist
            await expect(
                vw.checkpointNominee(nominee, chainId + 1)
            ).to.be.revertedWithCustomError(vw, "NomineeDoesNotExist");

            // Try to vote batch with incorrect array lengths
            await expect(
                vw.voteForNomineeWeightsBatch([nominee], [], [])
            ).to.be.revertedWithCustomError(vw, "WrongArrayLength");
            await expect(
                vw.voteForNomineeWeightsBatch([nominee], [chainId], [])
            ).to.be.revertedWithCustomError(vw, "WrongArrayLength");
            await expect(
                vw.voteForNomineeWeightsBatch([nominee], [], [maxVoteWeight])
            ).to.be.revertedWithCustomError(vw, "WrongArrayLength");
            await expect(
                vw.voteForNomineeWeightsBatch([], [chainId], [maxVoteWeight])
            ).to.be.revertedWithCustomError(vw, "WrongArrayLength");

            // Try to get next allowed voting times with wrong params
            await expect(
                vw.getNextAllowedVotingTimes([nominee], [], [])
            ).to.be.revertedWithCustomError(vw, "WrongArrayLength");
            await expect(
                vw.getNextAllowedVotingTimes([nominee], [chainId], [])
            ).to.be.revertedWithCustomError(vw, "WrongArrayLength");
            await expect(
                vw.getNextAllowedVotingTimes([], [chainId], [])
            ).to.be.revertedWithCustomError(vw, "WrongArrayLength");
            await expect(
                vw.getNextAllowedVotingTimes([], [chainId], [signers[1].address])
            ).to.be.revertedWithCustomError(vw, "WrongArrayLength");
            // Nominee that does not exist
            await expect(
                vw.getNextAllowedVotingTimes([nominee], [chainId + 1], [signers[1].address])
            ).to.be.revertedWithCustomError(vw, "NomineeDoesNotExist");
        });

        it("Vote for the nominees separately", async function () {
            // Lock one OLAS into veOLAS
            await olas.approve(ve.address, oneOLASBalance);
            await ve.createLock(oneOLASBalance, oneYear);

            // Add a nominee
            let nominee = signers[1].address;
            await vw.addNomineeEVM(nominee, chainId);
            nominee = convertAddressToBytes32(nominee);

            // Get the next point timestamp where votes are written after voting
            let block = await ethers.provider.getBlock("latest");
            let nextTime = getNextTime(block.timestamp);

            // Make sure the initial weight is zero
            let weight = await vw.nomineeRelativeWeight(nominee, chainId, block.timestamp);
            expect(weight.relativeWeight).to.equal(0);
            weight = await vw.nomineeRelativeWeight(nominee, chainId, nextTime);
            expect(weight.relativeWeight).to.equal(0);

            // Vote for the nominee
            await vw.voteForNomineeWeights(nominee, chainId, maxVoteWeight / 2);


            // Add one more nominee
            let nominee2 = signers[2].address;
            await vw.addNomineeEVM(nominee2, chainId);
            nominee2 = convertAddressToBytes32(nominee2);

            // Make sure the initial weight is zero
            weight = await vw.nomineeRelativeWeight(nominee2, chainId, nextTime);
            expect(weight.relativeWeight).to.equal(0);

            // Vote for another nominee
            await vw.voteForNomineeWeights(nominee2, chainId, maxVoteWeight / 2);


            // Check the current nominee weight
            weight = await vw.getNomineeWeight(nominee, chainId);
            expect(weight).to.be.greaterThan(0);
            // Check the sum of nominee weights
            const sumWeights = await vw.getWeightsSum();
            expect(sumWeights).to.be.greaterThan(0);

            // Check relative weights that must represent a half for each
            weight = await vw.nomineeRelativeWeight(nominee, chainId, nextTime);
            expect(Number(weight.relativeWeight) / E18).to.equal(0.5);
            weight = await vw.nomineeRelativeWeight(nominee2, chainId, nextTime);
            expect(Number(weight.relativeWeight) / E18).to.equal(0.5);

            // Write nominee weight and try to get one from the distant future
            weight = await vw.callStatic.nomineeRelativeWeightWrite(nominee, chainId, nextTime * 2);
            expect(weight.relativeWeight).to.equal(0);

            // Checkpoint and checkpoint nominee
            await vw.checkpoint();
            await vw.checkpointNominee(nominee, chainId);

            // Get next allowed voting times
            block = await ethers.provider.getBlock("latest");
            nextTime = (await vw.WEIGHT_VOTE_DELAY()).add(block.timestamp);
            const nextTimes = await vw.getNextAllowedVotingTimes([nominee, nominee2], [chainId, chainId],
                [deployer.address, deployer.address]);
            for (let i = 0; i < nextTimes.length; i++) {
                expect(nextTimes[i]).to.lessThanOrEqual(nextTime);
            }
        });

        it("Vote for the nominee after some time", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Lock one OLAS into veOLAS
            await olas.approve(ve.address, oneOLASBalance);
            await ve.createLock(oneOLASBalance, oneYear);

            // Add a nominee
            let nominee = signers[1].address;
            await vw.addNomineeEVM(nominee, chainId);
            nominee = convertAddressToBytes32(nominee);

            // Wait for several weeks
            await helpers.time.increase(oneWeek * 3);

            // Vote for the nominee
            await vw.voteForNomineeWeights(nominee, chainId, maxVoteWeight);

            // Get the next point timestamp where votes are written after voting
            const block = await ethers.provider.getBlock("latest");
            const nextTime = getNextTime(block.timestamp);

            // Check relative weights that must represent a half for each
            const weight = await vw.nomineeRelativeWeight(nominee, chainId, nextTime);
            expect(Number(weight.relativeWeight) / E18).to.equal(1);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Batch vote for the nominees", async function () {
            // Lock one OLAS into veOLAS
            await olas.approve(ve.address, oneOLASBalance);
            await ve.createLock(oneOLASBalance, oneYear);

            // Add nominees
            const numNominees = 2;
            let nominees = [signers[1].address, signers[2].address];
            const chainIds = new Array(numNominees).fill(chainId);
            for (let i = 0; i < numNominees; i++) {
                await vw.addNomineeEVM(nominees[i], chainIds[i]);
            }

            nominees = [convertAddressToBytes32(nominees[0]), convertAddressToBytes32(nominees[1])];

            // Get the next point timestamp where votes are written after voting
            const block = await ethers.provider.getBlock("latest");
            const nextTime = getNextTime(block.timestamp);

            // Vote for the nominees in batch
            const voteWeights = new Array(2).fill(maxVoteWeight / 2);
            await vw.voteForNomineeWeightsBatch(nominees, chainIds, voteWeights);

            // Check weights that must represent a half for each
            for (let i = 0; i < numNominees; i++) {
                const weight = await vw.nomineeRelativeWeight(nominees[i], chainIds[i], nextTime);
                expect(Number(weight.relativeWeight) / E18).to.equal(0.5);
            }
        });

        it("Voting several times week after week", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Lock one OLAS into veOLAS
            await olas.approve(ve.address, oneOLASBalance);
            await ve.createLock(oneOLASBalance, oneYear * 4);

            // Add a nominee
            let nominee = signers[1].address;
            await vw.addNomineeEVM(nominee, chainId);
            nominee = convertAddressToBytes32(nominee);

            // Vote for the nominee
            await vw.voteForNomineeWeights(nominee, chainId, maxVoteWeight);

            // Wait for next two weeks (must pass 10 days where one cannot vote)
            await helpers.time.increase(oneWeek * 2);

            // Vote for the nominee again
            await vw.voteForNomineeWeights(nominee, chainId, maxVoteWeight);

            // Get the next point timestamp where votes are written after voting
            const block = await ethers.provider.getBlock("latest");
            const nextTime = getNextTime(block.timestamp);

            // Check relative weights that must represent a half for each
            const weight = await vw.nomineeRelativeWeight(nominee, chainId, nextTime);
            expect(Number(weight.relativeWeight) / E18).to.equal(1);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Voting with veOLAS lock changing", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Add nominees
            const numNominees = 2;
            let nominees = [signers[2].address, signers[3].address];
            for (let i = 0; i < numNominees; i++) {
                await vw.addNomineeEVM(nominees[i], chainId);
            }
            nominees = [convertAddressToBytes32(nominees[0]), convertAddressToBytes32(nominees[1])];

            // Lock one OLAS into veOLAS by deployer and another account
            await olas.approve(ve.address, oneOLASBalance);
            await ve.createLock(oneOLASBalance, oneYear);
            const user = signers[1];
            await olas.transfer(user.address, oneOLASBalance);
            await olas.connect(user).approve(ve.address, oneOLASBalance);
            await ve.connect(user).createLock(oneOLASBalance, oneYear);

            // Vote for the nominee by the deployer
            await vw.voteForNomineeWeights(nominees[0], chainId, maxVoteWeight);
            // Vote for the nominee by the user
            await vw.connect(user).voteForNomineeWeights(nominees[1], chainId, maxVoteWeight);

            // Deployer increases the OLAS amount in veOLAS
            await olas.approve(ve.address, oneOLASBalance);
            await ve.increaseAmount(oneOLASBalance);

            // Wait for several weeks
            await helpers.time.increase(oneWeek * 3);

            // Vote for the nominee by the deployer
            await vw.voteForNomineeWeights(nominees[0], chainId, maxVoteWeight);
            // Vote for the nominee by the user
            await vw.connect(user).voteForNomineeWeights(nominees[1], chainId, maxVoteWeight);

            // Get the next point timestamp where votes are written after voting
            let block = await ethers.provider.getBlock("latest");
            let nextTime = getNextTime(block.timestamp);

            // Check relative weights that must represent a half for each
            const weights = [
                await vw.nomineeRelativeWeight(nominees[0], chainId, nextTime),
                await vw.nomineeRelativeWeight(nominees[1], chainId, nextTime)
            ];
            // nominees[0] weight: 666666666680682666, nominees[1] weight: 333333333319317333; the ratio is 2:1
            expect(Number(weights[0].relativeWeight) / E18).to.be.greaterThan(Number(weights[1].relativeWeight) / E18);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Changing votes after two weeks", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Add nominees
            const numNominees = 3;
            let nominees = [signers[2].address, signers[3].address, signers[4].address];
            for (let i = 0; i < numNominees; i++) {
                await vw.addNomineeEVM(nominees[i], chainId);
            }
            nominees = [convertAddressToBytes32(nominees[0]), convertAddressToBytes32(nominees[1]),
                convertAddressToBytes32(nominees[2])];

            let weights = [2000, 7000, 1000];
            const chainIds = new Array(numNominees).fill(chainId);

            // Lock one OLAS into veOLAS by deployer and another account
            await olas.approve(ve.address, oneOLASBalance);
            await ve.createLock(oneOLASBalance, oneYear);

            // Vote for the nominees
            await vw.voteForNomineeWeightsBatch(nominees, chainIds, weights);

            // Wait for two weeks
            await helpers.time.increase(oneWeek * 2);

            // Vote for the nominees again with different weights
            weights = [9000, 500, 500];
            // Having weights too high after spending all the voting power results in the overflow
            await expect(
                vw.voteForNomineeWeightsBatch(nominees, chainIds, weights)
            ).to.be.revertedWithCustomError(vw, "Overflow");

            // The first weight must be no bigger than the first one used before, so no more than 2000
            // The second weight must be no bigger than the addition of a difference between first weights:
            // 2000 - 1000 = 1000, so the maximum second weight must be 7000 + 1000 = 8000, or below
            weights = [1000, 8000, 1000];
            await vw.voteForNomineeWeightsBatch(nominees, chainIds, weights);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Remove nominee and retrieve voting power", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Lock one OLAS into veOLAS
            await olas.approve(ve.address, oneOLASBalance);
            await ve.createLock(oneOLASBalance, oneYear);

            const numNominees = 2;
            // Add nominees and get their bytes32 addresses
            let nominees = [signers[1].address, signers[2].address];
            for (let i = 0; i < numNominees; i++) {
                await vw.addNomineeEVM(nominees[i], chainId);
                nominees[i] = convertAddressToBytes32(nominees[i]);
            }

            // Vote for the first nominee
            await vw.voteForNomineeWeights(nominees[0], chainId, maxVoteWeight);

            // Get the set of nominees
            let setNominees = await vw.getAllNominees();
            // Check that the length is 3 (including the zero one)
            expect(setNominees.length).to.equal(3);

            // Get the first nominee id
            let id = await vw.getNomineeId(nominees[0], chainId);
            // The id must be equal to 1
            expect(id).to.equal(1);
            // Get the second nominee id
            id = await vw.getNomineeId(nominees[1], chainId);
            // The id must be equal to 2
            expect(id).to.equal(2);

            // Try to remove the nominee not by the owner
            await expect(
                vw.connect(signers[1]).removeNominee(nominees[0], chainId)
            ).to.be.revertedWithCustomError(vw, "OwnerOnly");

            // Remove the nominee
            await vw.removeNominee(nominees[0], chainId);

            // Get the set of removed nominees
            const numRemovedNominees = await vw.getNumRemovedNominees();
            expect(numRemovedNominees).to.equal(1);
            const setRemovedNominees = await vw.getAllRemovedNominees();
            // The set itself has one more zero-th empty element
            expect(setRemovedNominees.length).to.equal(2);
            expect(numRemovedNominees).to.equal(setRemovedNominees.length - 1);
            // Get removed nominee Id
            id = await vw.getRemovedNomineeId(nominees[0], chainId);
            expect(id).to.equal(1);
            // Check the removed nominee id
            const remNominee = await vw.getRemovedNominee(id);
            expect(remNominee.account).to.equal(nominees[0]);
            expect(remNominee.chainId).to.equal(chainId);

            // Get the removed nominee Id
            id = await vw.getNomineeId(nominees[0], chainId);
            expect(id).to.equal(0);

            // Try to remove the nominee again
            await expect(
                vw.removeNominee(nominees[0], chainId)
            ).to.be.revertedWithCustomError(vw, "NomineeDoesNotExist");

            // Get the id for the second nominee that was shifted from 2 to 1
            id = await vw.getNomineeId(nominees[1], chainId);
            expect(id).to.equal(1);

            // Try to add a removed nominee
            await expect(
                vw.addNomineeEVM(convertBytes32ToAddress(nominees[0]), chainId)
            ).to.be.revertedWithCustomError(vw, "NomineeRemoved");

            // Try to vote for a removed nominee
            await expect(
                vw.voteForNomineeWeights(nominees[0], chainId, maxVoteWeight)
            ).to.be.revertedWithCustomError(vw, "NomineeRemoved");

            // Checkpoint the nominee weight, which is still possible
            await vw.checkpointNominee(nominees[0], chainId);

            // Wait for two weeks
            await helpers.time.increase(oneWeek * 2);

            // Try to vote for the second nominee - fails because the voting power is not retrieved
            await expect(
                vw.voteForNomineeWeights(nominees[1], chainId, maxVoteWeight)
            ).to.be.revertedWithCustomError(vw, "Overflow");

            // Retrieve the nominee voting power
            await vw.revokeRemovedNomineeVotingPower(nominees[0], chainId);

            // Try to retrieve voting power from the same nominee that was already retrieved from
            await expect(
                vw.revokeRemovedNomineeVotingPower(nominees[0], chainId)
            ).to.be.revertedWithCustomError(vw, "ZeroValue");

            // Try to retrieve voting power from the nominee that was not removed
            await expect(
                vw.revokeRemovedNomineeVotingPower(nominees[1], chainId)
            ).to.be.revertedWithCustomError(vw, "NomineeNotRemoved");

            // Now it's possible to case a vote for another nominee
            await vw.voteForNomineeWeights(nominees[1], chainId, maxVoteWeight);

            // Checkpoint the nominee
            await vw.checkpointNominee(nominees[1], chainId);
            // The removed nominee has still some weighting power
            let weight = await vw.getNomineeWeight(nominees[1], chainId);
            expect(weight).to.gt(0);

            // Remove the second nominee
            await vw.removeNominee(nominees[1], chainId);

            // Check the second removed nominee Id
            id = await vw.getRemovedNomineeId(nominees[1], chainId);
            expect(id).to.equal(2);
            // Check the actual number of removed nominees
            expect(await vw.getNumRemovedNominees()).to.equal(2);

            // After removing, the weight must be zero
            weight = await vw.getNomineeWeight(nominees[1], chainId);
            expect(weight).to.equal(0);

            // Wait for two weeks
            await helpers.time.increase(oneWeek * 2);

            // Checkpoint the removed nominee and check its weight again that must be zero
            await vw.checkpointNominee(nominees[1], chainId);
            weight = await vw.getNomineeWeight(nominees[1], chainId);
            expect(weight).to.equal(0);

            // Wait until the lock expires
            await helpers.time.increase(oneYear);

            // Retrieve the second nominee voting power
            await vw.revokeRemovedNomineeVotingPower(nominees[1], chainId);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Should fail when the dispenser is not correctly called", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Lock one OLAS into veOLAS
            await olas.approve(ve.address, oneOLASBalance);
            await ve.createLock(oneOLASBalance, oneYear);

            // Add nominee and get their bytes32 addresses
            let nominee = signers[1].address;
            await vw.addNomineeEVM(nominee, chainId);
            nominee = convertAddressToBytes32(nominee);

            // Set the dispenser
            await vw.changeDispenser(deployer.address);

            // Try to add nominee
            await expect(
                vw.addNomineeEVM(convertBytes32ToAddress(nominee), chainId + 1)
            ).to.be.reverted;

            // Try to remove nominee
            await expect(
                vw.removeNominee(nominee, chainId)
            ).to.be.reverted;

            // Restore to the state of the snapshot
            await snapshot.restore();
        });
    });
});
