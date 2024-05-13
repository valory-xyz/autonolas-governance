/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Deployment", function () {
    let signers;
    let EOA;
    let safeSignersCM;
    let safeSignersCMAddresses;
    let safeSignersValoryAddresses;
    // Production threshold for the DAO multisig is 6
    const safeThresholdCM = 6;
    // Production threshold for the Valory multisig is 2
    const safeThresholdValory = 2;
    let nonce =  0;
    const AddressZero = "0x" + "0".repeat(40);
    const adminRole = ethers.utils.id("TIMELOCK_ADMIN_ROLE");
    const proposerRole = ethers.utils.id("PROPOSER_ROLE");
    const executorRole = ethers.utils.id("EXECUTOR_ROLE");
    const cancellerRole = ethers.utils.id("CANCELLER_ROLE");
    const safeContracts = require("@gnosis.pm/safe-contracts");
    const fs = require("fs");
    let gnosisSafeL2;
    let gnosisSafeProxyFactory;
    const _1kOLASBalance = "1000" + "0".repeat(18);
    const _2kOLASBalance = "2000" + "0".repeat(18);
    const _3kOLASBalance = "3000" + "0".repeat(18);
    const _4kOLASBalance = "4000" + "0".repeat(18);
    const oneYear = 365 * 86400;
    let veOLASSigners;
    let buOLASSigners;
    // For testing of the balances creation for initial DAO members, create the file claimableBalances.json in the root folder,
    // or copy it from scripts/deployment/dummyClaimableBalances.json.
    const jsonFile = "claimableBalances.json";

    // Mock of brute force to get OLAS address
    function bruteForceOLAS(deploymentAddress) {
        return ethers.utils.id("0x0001a5");
    }

    // Mock of brute force to get veOLAS address
    function bruteForceVeOLAS(deploymentAddress, olasAddress) {
        return ethers.utils.id("0x7e01a5");
    }

    beforeEach(async function () {
        const GnosisSafeL2 = await ethers.getContractFactory("GnosisSafeL2");
        gnosisSafeL2 = await GnosisSafeL2.deploy();
        await gnosisSafeL2.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        signers = await ethers.getSigners();
        EOA = signers[0];
        // Get the full set of CM signer EOAs (9)
        safeSignersCM = signers.slice(1, 10).map(
            function (currentSigner) {
                return currentSigner;
            }
        );
        // Get the full set of CM signers addresses (9)
        safeSignersCMAddresses = signers.slice(1, 10).map(
            function (currentSigner) {
                return currentSigner.address;
            }
        );
        // Get the full set of Valory multisig signers addresses (3)
        safeSignersValoryAddresses = [signers[11].address, signers[12].address, signers[13].address];

        // Simulate claimable balances JSON data
        veOLASSigners = [signers[15], signers[16], signers[17]];
        buOLASSigners = [signers[16], signers[17], signers[18], signers[19]];

        // signers[16] and signers[17] have both veOLAS and buOLAS for claiming
        let claimableBalancesJSON = {
            "veOLAS": {
                "addresses": [veOLASSigners[0].address, veOLASSigners[1].address, veOLASSigners[2].address],
                "amounts": [_1kOLASBalance, _2kOLASBalance, _3kOLASBalance],
                "lockTimes": [oneYear, 2 * oneYear, 3 * oneYear]
            },
            "buOLAS": {
                "addresses": [buOLASSigners[0].address, buOLASSigners[1].address, buOLASSigners[2].address, buOLASSigners[3].address],
                "amounts": [_1kOLASBalance, _2kOLASBalance, _3kOLASBalance, _4kOLASBalance],
                "numSteps": [1, 2, 3, 4]
            }
        };

        // Write the json file with the setup to simulate the read later in the flow
        fs.writeFileSync(jsonFile, JSON.stringify(claimableBalancesJSON));
    });

    context("Initialization", async function () {
        it("Changing owner", async function () {
            const FACTORY = await ethers.getContractFactory("DeploymentFactory");
            const factory = await FACTORY.connect(EOA).deploy();
            await factory.deployed();

            const owner = signers[0];
            const account = signers[1];

            // Trying to change owner from a non-owner account address
            await expect(
                factory.connect(account).changeOwner(account.address)
            ).to.be.revertedWithCustomError(factory, "OwnerOnly");

            // Trying to change owner for the zero address
            await expect(
                factory.connect(owner).changeOwner(AddressZero)
            ).to.be.revertedWithCustomError(factory, "ZeroAddress");

            // Changing the owner
            await factory.connect(owner).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                factory.connect(owner).changeOwner(owner.address)
            ).to.be.revertedWithCustomError(factory, "OwnerOnly");
        });

        it("Checking computed addresses", async function () {
            const FACTORY = await ethers.getContractFactory("DeploymentFactory");
            const factory = await FACTORY.connect(EOA).deploy();
            await factory.deployed();

            // Check that the initial addresses are zeros
            expect(await factory.connect(EOA).olasAddress()).to.equal(AddressZero);
            expect(await factory.connect(EOA).veOLASAddress()).to.equal(AddressZero);

            // Pre-compute OLAS address
            const olasSalt = bruteForceOLAS(factory.address);
            let preAddress = await factory.computeOLASAddress(olasSalt);
            // Deploy OLAS and check with the pre-computed address
            await factory.deployOLAS(olasSalt);
            const olasAddress = await factory.olasAddress();
            expect(olasAddress).to.equal(preAddress);

            // Pre-compute veOLAS address
            const veSalt = bruteForceOLAS(factory.address, olasAddress);
            preAddress = await factory.computeVeOLASAddress(veSalt, olasAddress);
            // Deploy OLAS and check with the pre-computed address
            await factory.deployVeOLAS(veSalt, olasAddress);
            expect(await factory.veOLASAddress()).to.equal(preAddress);
        });
    });

    // Verify timelock roles for the specified account address and array of corresponding roles
    async function checkTimelockRoles(timelock, accountAddress, grantedRoleArr) {
        expect(await timelock.hasRole(adminRole, accountAddress)).to.equal(grantedRoleArr[0]);
        expect(await timelock.hasRole(executorRole, accountAddress)).to.equal(grantedRoleArr[1]);
        expect(await timelock.hasRole(proposerRole, accountAddress)).to.equal(grantedRoleArr[2]);
        expect(await timelock.hasRole(cancellerRole, accountAddress)).to.equal(grantedRoleArr[3]);
    }

    context("Deployment script testing", async function () {
        it("Following specified steps to deploy contracts", async function () {
            // 0. EOA creates a Valory multisig with 3 signers and 2 threshold
            let setupData = gnosisSafeL2.interface.encodeFunctionData(
                "setup",
                // signers, threshold, to_address, data, fallback_handler, payment_token, payment, payment_receiver
                [safeSignersValoryAddresses, safeThresholdValory, AddressZero, "0x", AddressZero, AddressZero, 0, AddressZero]
            );
            let proxyAddress = await safeContracts.calculateProxyAddress(gnosisSafeProxyFactory, gnosisSafeL2.address,
                setupData, nonce);
            await gnosisSafeProxyFactory.createProxyWithNonce(gnosisSafeL2.address, setupData, nonce).then((tx) => tx.wait());
            const valoryMultisig = await ethers.getContractAt("GnosisSafeL2", proxyAddress);

            // 1. EOA creates community multisig (CM) of the DAO with Gnosis Safe, that has 9 signers and 6 threshold;
            nonce++;
            setupData = gnosisSafeL2.interface.encodeFunctionData(
                "setup",
                // signers, threshold, to_address, data, fallback_handler, payment_token, payment, payment_receiver
                [safeSignersCMAddresses, safeThresholdCM, AddressZero, "0x", AddressZero, AddressZero, 0, AddressZero]
            );
            proxyAddress = await safeContracts.calculateProxyAddress(gnosisSafeProxyFactory, gnosisSafeL2.address,
                setupData, nonce);
            await gnosisSafeProxyFactory.createProxyWithNonce(gnosisSafeL2.address, setupData, nonce).then((tx) => tx.wait());
            const CM = await ethers.getContractAt("GnosisSafeL2", proxyAddress);

            // !!!!!!!!!!!!!!!!!!!!!!!! ORIGINAL DEPLOYMENT STEPS !!!!!!!!!!!!!!!!!!!!!!!!
            // 2. EOA to deploy DeploymentFactory and get the deploymentAddress of DeploymentFactory;
            const FACTORY = await ethers.getContractFactory("DeploymentFactory");
            const factory = await FACTORY.connect(EOA).deploy();
            await factory.deployed();
            // End of 2: EOA is the owner of: factory

            // 3. Brutforce salt for vanity address OLAS (deploymentAddress + bytecode);
            const olasSalt = bruteForceOLAS(factory.address);

            // 4. EOA to deploy OLAS contract via DeploymentFactory (becoming its owner and minter);
            await factory.connect(EOA).deployOLAS(olasSalt);
            const olasAddress = await factory.olasAddress();
            const olas = await ethers.getContractAt("OLAS", olasAddress);
            expect(await EOA.getAddress()).to.equal(await olas.owner());
            expect(await EOA.getAddress()).to.equal(await olas.minter());
            // End of 4: EOA is the owner of: factory, OLAS
            //           EOA is the minter of: OLAS

            // 5. EOA to deploy the Timelock contract with the proposer ("PROPOSER_ROLE"), executor ("EXECUTOR_ROLE"),
            // and canceller ("CANCELLER_ROLE") roles given to the CM (via deployment with `proposers` and `executors` parameters being the CM address);
            const minDelay = 5; // 5 blocks (for testing purposes, to not wait for too many mined blocks)
            const executors = [CM.address];
            const proposers = [CM.address];
            const Timelock = await ethers.getContractFactory("Timelock");
            const timelock = await Timelock.connect(EOA).deploy(minDelay, proposers, executors);
            await timelock.deployed();

            // Verify CM address roles
            await checkTimelockRoles(timelock, CM.address, [false, true, true, true]);
            // End of 5: EOA is the owner of: factory, OLAS
            //           EOA is the admin of timelock
            //           EOA is the minter of: OLAS
            //           CM is the proposer, canceller and executor of timelock
            //           timelock is the admin of timelock

            // 6. Brutforce salt for vanity address veOLAS (deploymentAddress + OLAS address + bytecode);
            const veSalt = bruteForceVeOLAS(factory.address, olasAddress);

            // 7. EOA to deploy veOLAS contract via DeploymentFactory pointed to OLAS;
            await factory.connect(EOA).deployVeOLAS(veSalt, olas.address);
            const veOLASAddress = await factory.veOLASAddress();
            const ve = await ethers.getContractAt("veOLAS", veOLASAddress);
            // End of 7: EOA is the owner of: factory, OLAS
            //           EOA is the admin of timelock
            //           EOA is the minter of: OLAS
            //           CM is the proposer, canceller and executor of timelock
            //           timelock is the admin of timelock

            // 8. EOA to deploy GovernorOLAS contract with veOLAS and Timelock addresses as input parameters
            // and other defined governor-related parameters;
            const initialVotingDelay = 13091; // 2 days in blocks (assuming 13.2s per block)
            const initialVotingPeriod = 19636; // 3 days in blocks (assuming 13.2s per block)
            const initialProposalThreshold = "1" + "0" * 21; // 1000 OLAS
            const quorum = 4;
            const GovernorOLAS = await ethers.getContractFactory("GovernorOLAS");
            const governor = await GovernorOLAS.connect(EOA).deploy(ve.address, timelock.address, initialVotingDelay,
                initialVotingPeriod, initialProposalThreshold, quorum);
            await governor.deployed();
            // End of 8: EOA is the owner of: factory, OLAS
            //           EOA is the admin of timelock
            //           EOA is the minter of: OLAS
            //           CM is the proposer, canceller and executor of timelock
            //           timelock is the admin of timelock
            //           timelock is the governance of governor

            // 9. EOA to give admin ("TIMELOCK_ADMIN_ROLE"), proposer ("PROPOSER_ROLE"), executor ("EXECUTOR_ROLE"),
            // and canceller ("CANCELLER_ROLE") roles to GovernorOLAS from Timelock (in separate transactions via `grantRole()` calls);
            await timelock.connect(EOA).grantRole(adminRole, governor.address);
            await timelock.connect(EOA).grantRole(executorRole, governor.address);
            await timelock.connect(EOA).grantRole(proposerRole, governor.address);
            await timelock.connect(EOA).grantRole(cancellerRole, governor.address);
            // End of 9: EOA is the owner of: factory, OLAS
            //           EOA is the admin of timelock
            //           EOA is the minter of: OLAS
            //           CM is the proposer, canceller and executor of timelock
            //           timelock is the admin of timelock
            //           timelock is the governance of governor
            //           governor is the admin, proposer, canceller and executor of timelock

            // Verify governor address roles
            await checkTimelockRoles(timelock, governor.address, [true, true, true, true]);

            // 10. EOA to deploy buOLAS contract pointed to OLAS;
            const BU = await ethers.getContractFactory("buOLAS");
            const bu = await BU.connect(EOA).deploy(olas.address, "Burnable Locked OLAS", "buOLAS");
            await bu.deployed();
            // End of 10: EOA is the owner of: factory, OLAS, buOLAS
            //            EOA is the admin of timelock
            //            EOA is the minter of: OLAS
            //            CM is the proposer, canceller and executor of timelock
            //            timelock is the admin of timelock
            //            timelock is the governance of governor
            //            governor is the admin, proposer, canceller and executor of timelock

            // 11. EOA to mint initial OLAS supply for DAO treasury (sent to Timelock), DAO members (sent to Sale contract (deprecated)),
            // Valory (sent to Valory multisig);
            const initSupply = "5265" + "0".repeat(23);
            // Numbers below must accumulate to initSupply
            const timelockSupply = "1" + "0".repeat(26);
            const saleSupply = "3015" + "0".repeat(23);
            const valorySupply = "125" + "0".repeat(24);
            // Mint for Timelock, Sale and Valory multisig
            await olas.connect(EOA).mint(timelock.address, timelockSupply);
            await olas.connect(EOA).mint(EOA.address, saleSupply);
            await olas.connect(EOA).mint(valoryMultisig.address, valorySupply);

            // Check the balance of contracts to be equal to the initSupply in total
            const balanceTimelock = BigInt(await olas.balanceOf(timelock.address));
            const balanceSale = BigInt(await olas.balanceOf(EOA.address));
            const balanceValory = BigInt(await olas.balanceOf(valoryMultisig.address));
            const sumBalance = balanceTimelock + balanceSale + balanceValory;
            expect(sumBalance).to.equal(BigInt(initSupply));
            // End of 11: EOA is the owner of: factory, OLAS, buOLAS, sale
            //            EOA is the admin of timelock
            //            EOA is the minter of: OLAS
            //            CM is the proposer, canceller and executor of timelock
            //            timelock is the admin of timelock
            //            timelock is the governance of governor
            //            governor is the admin, proposer, canceller and executor of timelock
            //            Balances in OLAS: timelock: 100 million, EOA (to simulate deprecated sale): 301.5 million, valory multisig: 125 million

            // 12. EOA to transfer its minting and its ownership rights of OLAS to Timelock by calling `changeMinter(Timelock)` and `changeOwner(Timelock)`;
            // 13. EOA to transfer ownership rights of buOLAS to Timelock calling `changeOwner(Timelock)`;
            await olas.connect(EOA).changeMinter(timelock.address);
            await olas.connect(EOA).changeOwner(timelock.address);
            await bu.connect(EOA).changeOwner(timelock.address);

            // Try to change owner of OLAS by EOA once again
            await expect(
                olas.connect(EOA).changeOwner(timelock.address)
            ).to.be.revertedWithCustomError(olas, "ManagerOnly");

            // Try to change owner of buOLAS by EOA once again
            await expect(
                bu.connect(EOA).changeOwner(timelock.address)
            ).to.be.revertedWithCustomError(bu, "OwnerOnly");

            // End of 13: EOA is the owner of: factory
            //            EOA is the admin of timelock
            //            CM is the proposer, canceller and executor of timelock
            //            timelock is the owner of: OLAS, buOLAS
            //            valoryMultisig is the owner of: sale
            //            timelock is the minter of: OLAS
            //            timelock is the admin of timelock
            //            timelock is the governance of governor
            //            governor is the admin, proposer, canceller and executor of timelock
            //            Balances in OLAS: timelock: 100 million, EOA (to simulate deprecated sale): 301.5 million, valory multisig: 125 million

            // 14. EOA to revoke self admin rights from the Timelock (via `renounceRole()`);
            await timelock.connect(EOA).renounceRole(adminRole, EOA.address);

            // Verify EOA address roles to be all revoked
            await checkTimelockRoles(timelock, EOA.address, [false, false, false, false]);
            // End of 14: EOA is the owner of: factory
            //            CM is the proposer, canceller and executor of timelock
            //            timelock is the owner of: OLAS, buOLAS
            //            valoryMultisig is the owner of: sale
            //            timelock is the minter of: OLAS
            //            timelock is the admin of timelock
            //            timelock is the governance of governor
            //            governor is the admin, proposer, canceller and executor of timelock
            //            Balances in OLAS: timelock: 100 million, EOA (to simulate deprecated sale): 301.5 million, valory multisig: 125 million

            // veOLAS and buOLAS claim from the deprecated Sale contract

            // 15. EOA to revoke self ownership rights from DeploymentFactory to Null Address (via `changeOwner()`)
            await factory.connect(EOA).changeOwner("0x000000000000000000000000000000000000dEaD");
            // Try to change the owner of factory by EOA once again
            await expect(
                factory.connect(EOA).changeOwner(EOA.address)
            ).to.be.revertedWithCustomError(factory, "OwnerOnly");
            // End of 15: CM is the proposer, canceller and executor of timelock
            //            timelock is the owner of: OLAS, buOLAS
            //            valoryMultisig is the owner of: sale
            //            timelock is the minter of: OLAS
            //            timelock is the admin of timelock
            //            timelock is the governance of governor
            //            governor is the admin, proposer, canceller and executor of timelock
            //            Balances in OLAS: timelock: 100 million, valory multisig: 125 million
            //            Balances in veOLAS and buOLAS: 301.5 million as all successfully claimed

            // !!!!!!!!!!!!!!!!!!!!!!!! SUPPLEMENTAL DEPLOYMENT STEPS !!!!!!!!!!!!!!!!!!!!!!!!
            // 16. EOA to deploy wveOLAS contract pointed to veOLAS and OLAS;
            const WVE = await ethers.getContractFactory("wveOLAS");
            const wve = await WVE.connect(EOA).deploy(ve.address, olas.address);
            await wve.deployed();

            // 17. EOA to deploy GovernorOLAS contract with wveOLAS and Timelock addresses as input parameters
            // and other defined governor-related parameters;
            const governorTwo = await GovernorOLAS.connect(EOA).deploy(wve.address, timelock.address, initialVotingDelay,
                initialVotingPeriod, initialProposalThreshold, quorum);
            await governor.deployed();

            // 18. Timelock to revoke admin ("TIMELOCK_ADMIN_ROLE"), proposer ("PROPOSER_ROLE"), executor ("EXECUTOR_ROLE"),
            // and canceller ("CANCELLER_ROLE") roles from original GovernorOLAS, give admin ("TIMELOCK_ADMIN_ROLE"), proposer ("PROPOSER_ROLE"),
            // executor ("EXECUTOR_ROLE"), and canceller ("CANCELLER_ROLE") roles to a new GovernorOLAS based on wveOLAS (via voting).
            // Prepare the batch data for the timelock
            const sTargets = new Array(8).fill(timelock.address);
            const sValues = new Array(8).fill(0);
            const sCallDatas = [
                timelock.interface.encodeFunctionData("revokeRole", [adminRole, governor.address]),
                timelock.interface.encodeFunctionData("revokeRole", [executorRole, governor.address]),
                timelock.interface.encodeFunctionData("revokeRole", [proposerRole, governor.address]),
                timelock.interface.encodeFunctionData("revokeRole", [cancellerRole, governor.address]),
                timelock.interface.encodeFunctionData("grantRole", [adminRole, governorTwo.address]),
                timelock.interface.encodeFunctionData("grantRole", [executorRole, governorTwo.address]),
                timelock.interface.encodeFunctionData("grantRole", [proposerRole, governorTwo.address]),
                timelock.interface.encodeFunctionData("grantRole", [cancellerRole, governorTwo.address])
            ];
            const bytes32Zeros = "0x" + "0".repeat(64);

            // Originate a Safe transaction from the CM as the timelock proposer
            nonce = await CM.nonce();
            let txHashData = await safeContracts.buildContractCall(timelock, "scheduleBatch",
                [sTargets, sValues, sCallDatas, bytes32Zeros, bytes32Zeros, minDelay], nonce, 0, 0);
            let signMessageData = new Array(safeSignersCM.length);
            for (let i = 0; i < safeSignersCM.length; i++) {
                signMessageData[i] = await safeContracts.safeSignMessage(safeSignersCM[i], CM, txHashData, 0);
            }
            await safeContracts.executeTx(CM, txHashData, signMessageData, 0);

            // Waiting for the minDelay number of blocks to pass
            for (let i = 0; i < minDelay; i++) {
                ethers.provider.send("evm_mine");
            }

            // Execute the proposed operation and check the execution result
            nonce = await CM.nonce();
            txHashData = await safeContracts.buildContractCall(timelock, "executeBatch",
                [sTargets, sValues, sCallDatas, bytes32Zeros, bytes32Zeros], nonce, 0, 0);
            for (let i = 0; i < safeSignersCM.length; i++) {
                signMessageData[i] = await safeContracts.safeSignMessage(safeSignersCM[i], CM, txHashData, 0);
            }
            await safeContracts.executeTx(CM, txHashData, signMessageData, 0);

            // Verify governor address roles
            await checkTimelockRoles(timelock, governor.address, [false, false, false, false]);
            // Verify governorTwo address roles
            await checkTimelockRoles(timelock, governorTwo.address, [true, true, true, true]);
        });
    });
});
