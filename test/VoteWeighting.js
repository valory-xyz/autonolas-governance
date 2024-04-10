/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("Voting Escrow OLAS", function () {
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
    const maxU256 = ethers.constants.MaxUint256;

    function getNextTime(ts) {
        return Math.floor((ts + oneWeek) / oneWeek) * oneWeek;
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
    });

    context("Adding nominees", async function () {
        it("Should fail with wrong nominee params", async function () {
            // Lock one OLAS into veOLAS
            await olas.approve(ve.address, oneOLASBalance);
            await ve.createLock(oneOLASBalance, oneYear);

            // Try to add a zero address nominee
            await expect(
                vw.addNominee(AddressZero, chainId)
            ).to.be.revertedWithCustomError(vw, "ZeroAddress");

            // Try to add a zero chain Id
            await expect(
                vw.addNominee(signers[1].address, 0)
            ).to.be.revertedWithCustomError(vw, "ZeroValue");

            // Try to add an overflow chain Id
            let overflowChainId = await vw.MAX_CHAIN_ID();
            overflowChainId = overflowChainId.add(1);
            await expect(
                vw.addNominee(signers[1].address, overflowChainId)
            ).to.be.revertedWithCustomError(vw, "Overflow");
        });

        it("Add nominee", async function () {
            // Lock one OLAS into veOLAS
            await olas.approve(ve.address, oneOLASBalance);
            await ve.createLock(oneOLASBalance, oneYear);

            // Add a nominee
            await vw.addNominee(signers[1].address, chainId);

            // Try to add the same nominee
            await expect(
                vw.addNominee(signers[1].address, chainId)
            ).to.be.revertedWithCustomError(vw, "NomineeAlreadyExists");

            // Check the nominee setup
            const numNominees = await vw.getNumNominees();
            expect(numNominees).to.equal(1);

            const nomineeChainId = await vw.getNominee(1);
            expect(nomineeChainId.nominee).to.equal(signers[1].address);
            expect(nomineeChainId.chainId).to.equal(chainId);

            const nomineeChainIds = await vw.getNominees(1, 1);
            expect(nomineeChainIds.nominees[0]).to.equal(signers[1].address);
            expect(nomineeChainIds.chainIds[0]).to.equal(chainId);

            let nomineeId = await vw.getNomineeId(signers[1].address, chainId);
            expect(nomineeId).to.equal(1);

            // Check the nominee Id of a nonexistent nominee
            nomineeId = await vw.getNomineeId(signers[1].address, chainId + 1);
            expect(nomineeId).to.equal(0);
        });

        it("Get nominees", async function () {
            // Lock one OLAS into veOLAS
            await olas.approve(ve.address, oneOLASBalance);
            await ve.createLock(oneOLASBalance, oneYear);

            // Add a nominee
            await vw.addNominee(signers[1].address, chainId);

            // Try to get the zero-th nominees
            await expect(
                vw.getNominee(0)
            ).to.be.revertedWithCustomError(vw, "ZeroValue");
            await expect(
                vw.getNominees(1, 0)
            ).to.be.revertedWithCustomError(vw, "ZeroValue");
            await expect(
                vw.getNominees(0, 1)
            ).to.be.revertedWithCustomError(vw, "ZeroValue");

            // Try to get the nonexistent nominee
            await expect(
                vw.getNominee(2)
            ).to.be.revertedWithCustomError(vw, "Overflow");
            await expect(
                vw.getNominees(2, 1)
            ).to.be.revertedWithCustomError(vw, "Overflow");
            await expect(
                vw.getNominees(1, 2)
            ).to.be.revertedWithCustomError(vw, "Overflow");
        });
    });

    context("Voting", async function () {
        it("Should fail with wrong input arguments", async function () {
            // Add a nominee
            let nominee = signers[1].address;
            await vw.addNominee(nominee, chainId);

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
            await vw.addNominee(nominee, chainId);
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
        });

        it("Vote for the nominees separately", async function () {
            // Lock one OLAS into veOLAS
            await olas.approve(ve.address, oneOLASBalance);
            await ve.createLock(oneOLASBalance, oneYear);

            // Add a nominee
            const nominee = signers[1].address;
            await vw.addNominee(nominee, chainId);

            // Get the next point timestamp where votes are written after voting
            const block = await ethers.provider.getBlock("latest");
            const nextTime = getNextTime(block.timestamp);

            // Make sure the initial weight is zero
            let weight = await vw.nomineeRelativeWeight(nominee, chainId, block.timestamp);
            expect(weight).to.equal(0);
            weight = await vw.nomineeRelativeWeight(nominee, chainId, nextTime);
            expect(weight).to.equal(0);

            // Vote for the nominee
            await vw.voteForNomineeWeights(nominee, chainId, maxVoteWeight / 2);


            // Add one more nominee
            const nominee2 = signers[2].address;
            await vw.addNominee(nominee2, chainId);

            // Make sure the initial weight is zero
            weight = await vw.nomineeRelativeWeight(nominee2, chainId, nextTime);
            expect(weight).to.equal(0);

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
            expect(Number(weight) / E18).to.equal(0.5);
            weight = await vw.nomineeRelativeWeight(nominee2, chainId, nextTime);
            expect(Number(weight) / E18).to.equal(0.5);

            // Write nominee weight and try to get one from the distant future
            weight = await vw.callStatic.nomineeRelativeWeightWrite(nominee, chainId, nextTime * 2);
            expect(weight).to.equal(0);

            // Checkpoint and checkpoint nominee
            await vw.checkpoint();
            await vw.checkpointNominee(nominee, chainId);
        });

        it("Vote for the nominee after some time", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Lock one OLAS into veOLAS
            await olas.approve(ve.address, oneOLASBalance);
            await ve.createLock(oneOLASBalance, oneYear);

            // Add a nominee
            const nominee = signers[1].address;
            await vw.addNominee(nominee, chainId);

            // Wait for several weeks
            await helpers.time.increase(oneWeek * 3);

            // Vote for the nominee
            await vw.voteForNomineeWeights(nominee, chainId, maxVoteWeight);

            // Get the next point timestamp where votes are written after voting
            const block = await ethers.provider.getBlock("latest");
            const nextTime = getNextTime(block.timestamp);

            // Check relative weights that must represent a half for each
            const weight = await vw.nomineeRelativeWeight(nominee, chainId, nextTime);
            expect(Number(weight) / E18).to.equal(1);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Batch vote for the nominees", async function () {
            // Lock one OLAS into veOLAS
            await olas.approve(ve.address, oneOLASBalance);
            await ve.createLock(oneOLASBalance, oneYear);

            // Add nominees
            const numNominees = 2;
            const nominees = [signers[1].address, signers[2].address];
            const chainIds = new Array(numNominees).fill(chainId);
            for (let i = 0; i < numNominees; i++) {
                await vw.addNominee(nominees[i], chainIds[i]);
            }

            // Get the next point timestamp where votes are written after voting
            const block = await ethers.provider.getBlock("latest");
            const nextTime = getNextTime(block.timestamp);

            // Vote for the nominees in batch
            const voteWeights = new Array(2).fill(maxVoteWeight / 2);
            await vw.voteForNomineeWeightsBatch(nominees, chainIds, voteWeights);

            // Check weights that must represent a half for each
            for (let i = 0; i < numNominees; i++) {
                const weight = await vw.nomineeRelativeWeight(nominees[i], chainIds[i], nextTime);
                expect(Number(weight) / E18).to.equal(0.5);
            }
        });

        it("Voting several times week after week", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Lock one OLAS into veOLAS
            await olas.approve(ve.address, oneOLASBalance);
            await ve.createLock(oneOLASBalance, oneYear);

            // Add a nominee
            const nominee = signers[1].address;
            await vw.addNominee(nominee, chainId);

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
            expect(Number(weight) / E18).to.equal(1);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });

        it("Voting with veOLAS lock changing", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Add nominees
            const numNominees = 2;
            const nominees = [signers[2].address, signers[3].address];
            for (let i = 0; i < numNominees; i++) {
                await vw.addNominee(nominees[i], chainId);
            }

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
            expect(Number(weights[0]) / E18).to.be.greaterThan(Number(weights[1]) / E18);

            // Restore to the state of the snapshot
            await snapshot.restore();
        });
    });
});
