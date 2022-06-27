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
    let multiSend;
    const _1kOLABalance = "1000" + "0".repeat(18);
    const _2kOLABalance = "2000" + "0".repeat(18);
    const _3kOLABalance = "3000" + "0".repeat(18);
    const _4kOLABalance = "4000" + "0".repeat(18);
    const oneYear = 365 * 86400;
    let veOLASSigners;
    let buOLASSigners;
    const jsonFile = "claimableBalances.json";

    // Mock of brute force to get OLAS address
    function bruteForceOLAS(deployAddress) {
        return ethers.utils.id("0x0001a5");
    }

    // Mock of brute force to get veOLAS address
    function bruteForceVeOLAS(deployAddress, olasAddress) {
        return ethers.utils.id("0x7e01a5");
    }

    beforeEach(async function () {
        const GnosisSafeL2 = await ethers.getContractFactory("GnosisSafeL2");
        gnosisSafeL2 = await GnosisSafeL2.deploy();
        await gnosisSafeL2.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        const MultiSend = await ethers.getContractFactory("MultiSendCallOnly");
        multiSend = await MultiSend.deploy();
        await multiSend.deployed();

        signers = await ethers.getSigners();
        EOA = signers[0];
        // Get the full set of CM signers addresses (9)
        safeSignersCMAddresses = signers.slice(1, 10).map(
            function (currentSigner) {
                return currentSigner.address;
            }
        );
        // Get CM signers array up to the threshold (6)
        safeSignersCM = signers.slice(1, 7);
        // Get the full set of Valory multisig signers addresses (3)
        safeSignersValoryAddresses = [signers[11].address, signers[12].address, signers[13].address];

        // Simulate claimable balances JSON data
        veOLASSigners = [signers[15], signers[16], signers[17]];
        buOLASSigners = [signers[16], signers[17], signers[18], signers[19]];

        // signers[16] and signers[17] have both veOLAS and buOLAS for claiming
        let claimableBalancesJSON = {
            "veOLAS": {
                "addresses": [veOLASSigners[0].address, veOLASSigners[1].address, veOLASSigners[2].address],
                "amounts": [_1kOLABalance, _2kOLABalance, _3kOLABalance],
                "lockTimes": [oneYear, 2 * oneYear, 3 * oneYear]
            },
            "buOLAS": {
                "addresses": [buOLASSigners[0].address, buOLASSigners[1].address, buOLASSigners[2].address, buOLASSigners[3].address],
                "amounts": [_1kOLABalance, _2kOLABalance, _3kOLABalance, _4kOLABalance],
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
            ).to.be.revertedWith("OwnerOnly");

            // Trying to change owner for the zero address
            await expect(
                factory.connect(owner).changeOwner(AddressZero)
            ).to.be.revertedWith("ZeroAddress");

            // Changing the owner
            await factory.connect(owner).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                factory.connect(owner).changeOwner(owner.address)
            ).to.be.revertedWith("OwnerOnly");
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

    // Signing and executing Gnosis Safe transaction based on the multisig instance, tx hash and signers
    async function signAndExecuteSafeTx(CM, txHashData) {
        let signMessageData = new Array(safeThresholdCM);
        for (let i = 0; i < signMessageData.length; i++) {
            signMessageData[i] = await safeContracts.safeSignMessage(safeSignersCM[i], CM, txHashData, 0);
        }
        await safeContracts.executeTx(CM, txHashData, signMessageData, 0);
    }

    context("Deployment script testing", async function () {
        it("Following specified steps to deploy contracts", async function () {
            // 0. EOA creates a Valory multisig
            let setupData = gnosisSafeL2.interface.encodeFunctionData(
                "setup",
                // signers, threshold, to_address, data, fallback_handler, payment_token, payment, payment_receiver
                [safeSignersValoryAddresses, safeThresholdValory, AddressZero, "0x", AddressZero, AddressZero, 0, AddressZero]
            );
            let proxyAddress = await safeContracts.calculateProxyAddress(gnosisSafeProxyFactory, gnosisSafeL2.address,
                setupData, nonce);
            await gnosisSafeProxyFactory.createProxyWithNonce(gnosisSafeL2.address, setupData, nonce).then((tx) => tx.wait());
            const valoryMultisig = await ethers.getContractAt("GnosisSafeL2", proxyAddress);

            // 1. EOA creates community multisig (CM) of the DAO with Gnosis Safe, that has 3 signers and 3 threshold;
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

            // 2. EOA to deploy deployFactory and get deployAddress of deployFactory;
            const FACTORY = await ethers.getContractFactory("DeploymentFactory");
            const factory = await FACTORY.connect(EOA).deploy();
            await factory.deployed();
            // End of 2: EOA is the owner of: factory

            // 3. Brutforce salt for vanity address OLAS (deployAddress + bytecode);
            const olasSalt = bruteForceOLAS(factory.address);

            // 4. EOA to deploy OLAS contract via deployFactory (becoming its owner and minter);
            await factory.deployOLAS(olasSalt);
            const olasAddress = await factory.olasAddress();
            // End of 4: EOA is the owner of: factory, OLAS
            //           factory is the minter of OLAS

            // 5. EOA changes owner and minter on OLAS contract to CM: call `changeMinter(CM)` and `changeOwner(CM)`;
            const olas = await ethers.getContractAt("OLAS", olasAddress);
            await olas.changeMinter(CM.address);
            await olas.changeOwner(CM.address);

            // Check that the owner can't be changed by the EOA now
            await expect(
                olas.connect(EOA).changeOwner(EOA.address)
            ).to.be.revertedWith("ManagerOnly");
            // End of 5: EOA is the owner of: factory
            //           CM is the owner and minter of: OLAS

            // 6. EOA to deploy the Timelock contract with the proposer ("PROPOSER_ROLE"), executor ("EXECUTOR_ROLE"),
            // and canceller ("CANCELLER_ROLE") roles given to the CM (via deployment with `proposers` and `executors` parameters being the CM address);
            const minDelay = 13091; // 2 days in blocks (assuming 13.2s per block)
            const executors = [CM.address];
            const proposers = [CM.address];
            const Timelock = await ethers.getContractFactory("Timelock");
            const timelock = await Timelock.deploy(minDelay, proposers, executors);
            await timelock.deployed();

            // Verify CM address roles
            await checkTimelockRoles(timelock, CM.address, [false, true, true, true]);
            // End of 6: EOA is the owner of: factory
            //           EOA is the admin of timelock
            //           CM is the owner and minter of: OLAS
            //           CM is the proposer, canceller and executor of timelock
            //           timelock is the admin of timelock

            // 7. Brutforce salt for vanity address veOLAS (deployAddress + OLAS address + bytecode);
            const veSalt = bruteForceVeOLAS(factory.address, olasAddress);

            // 8. EOA to deploy veOLAS contract via deployFactory pointed to OLAS;
            await factory.deployVeOLAS(veSalt, olas.address);
            const veOLASAddress = await factory.veOLASAddress();
            const ve = await ethers.getContractAt("veOLAS", veOLASAddress);
            // End of 8: EOA is the owner of: factory
            //           EOA is the admin of timelock
            //           CM is the owner and minter of: OLAS
            //           CM is the proposer, canceller and executor of timelock
            //           timelock is the admin of timelock

            // 9. EOA to deploy GovernorOLAS contract with veOLAS and Timelock addresses as input parameters
            // and other defined governor-related parameters;
            const initialVotingDelay = 13091; // 2 days in blocks (assuming 13.2s per block)
            const initialVotingPeriod = 19636; // 3 days in blocks (assuming 13.2s per block)
            const initialProposalThreshold = "1" + "0" * 21; // 1000 OLAS
            const quorum = 4;
            const GovernorOLAS = await ethers.getContractFactory("GovernorOLAS");
            const governor = await GovernorOLAS.deploy(ve.address, timelock.address, initialVotingDelay,
                initialVotingPeriod, initialProposalThreshold, quorum);
            await governor.deployed();
            // End of 9: EOA is the owner of: factory
            //           EOA is the admin of timelock
            //           CM is the owner and minter of: OLAS
            //           CM is the proposer, canceller and executor of timelock
            //           timelock is the admin of timelock
            //           timelock is the governance of governor

            // 10. EOA to give admin ("TIMELOCK_ADMIN_ROLE"), proposer ("PROPOSER_ROLE"), executor ("EXECUTOR_ROLE"),
            // and canceller ("CANCELLER_ROLE") roles to GovernorOLAS from Timelock (in separate transactions via `grantRole()` calls);
            await timelock.grantRole(adminRole, governor.address);
            await timelock.grantRole(executorRole, governor.address);
            await timelock.grantRole(proposerRole, governor.address);
            await timelock.grantRole(cancellerRole, governor.address);
            // End of 10: EOA is the owner of: factory
            //            EOA is the admin of timelock
            //            CM is the owner and minter of: OLAS
            //            CM is the proposer, canceller and executor of timelock
            //            timelock is the admin of timelock
            //            timelock is the governance of governor
            //            governor is the admin, proposer, canceller and executor of timelock

            // Verify governor address roles
            await checkTimelockRoles(timelock, governor.address, [true, true, true, true]);

            // 11. EOA to deploy buOLAS contract pointed to OLAS;
            const BU = await ethers.getContractFactory("buOLAS");
            const bu = await BU.deploy(olas.address, "Burnable Locked OLAS", "buOLAS");
            await bu.deployed();
            // End of 11: EOA is the owner of: factory, buOLAS
            //            EOA is the admin of timelock
            //            CM is the owner and minter of: OLAS
            //            CM is the proposer, canceller and executor of timelock
            //            timelock is the admin of timelock
            //            timelock is the governance of governor
            //            governor is the admin, proposer, canceller and executor of timelock

            // 12. EOA changes owner on buOLAS to CM: call `changeOwner(CM)`;
            await bu.connect(EOA).changeOwner(CM.address);
            // End of 12: EOA is the owner of: factory
            //            EOA is the admin of timelock
            //            CM is the owner of: OLAS, buOLAS
            //            CM is the minter of: OLAS
            //            CM is the proposer, canceller and executor of timelock
            //            timelock is the admin of timelock
            //            timelock is the governance of governor
            //            governor is the admin, proposer, canceller and executor of timelock

            // Verify the ownership of buOLAS contract
            await expect(
                bu.connect(EOA).changeOwner(EOA.address)
            ).to.be.revertedWith("OwnerOnly");

            // 13. EOA to deploy Sale contract pointed to OLAS, veOLAs and bOLAS;
            const SALE = await ethers.getContractFactory("Sale");
            const sale = await SALE.deploy(olas.address, ve.address, bu.address);
            await sale.deployed();
            // End of 13: EOA is the owner of: factory, sale
            //            EOA is the admin of timelock
            //            CM is the owner of: OLAS, buOLAS
            //            CM is the minter of: OLAS
            //            CM is the proposer, canceller and executor of timelock
            //            timelock is the admin of timelock
            //            timelock is the governance of governor
            //            governor is the admin, proposer, canceller and executor of timelock

            // 14. EOA changes the owner on Sale contract to CM: call `changeOwner(CM)`;
            await sale.connect(EOA).changeOwner(CM.address);
            await sale.deployed();

            // Verify the ownership of Sale contract
            await expect(
                sale.connect(EOA).changeOwner(EOA.address)
            ).to.be.revertedWith("OwnerOnly");
            // End of 14: EOA is the owner of: factory
            //            EOA is the admin of timelock
            //            CM is the owner of: OLAS, buOLAS, sale
            //            CM is the minter of: OLAS
            //            CM is the proposer, canceller and executor of timelock
            //            timelock is the admin of timelock
            //            timelock is the governance of governor
            //            governor is the admin, proposer, canceller and executor of timelock

            // 15. CM to mint initial OLAS supply for DAO treasury (sent to Timelock), DAO members (sent to Sale contract),
            // Valory (sent to Valory multisig);
            const initSupply = "5265" + "0".repeat(23);
            // Numbers below must accumulate to initSupply
            const timelockSupply = "1" + "0".repeat(26);
            const saleSupply = "3015" + "0".repeat(23);
            const valorySupply = "125" + "0".repeat(24);
            // Mint for Timelock, Sale and Valory multisig in a multisend batch transaction
            nonce = await CM.nonce();
            let callData = [olas.interface.encodeFunctionData("mint", [timelock.address, timelockSupply]),
                olas.interface.encodeFunctionData("mint", [sale.address, saleSupply]),
                olas.interface.encodeFunctionData("mint", [valoryMultisig.address, valorySupply])];
            let txs = [safeContracts.buildSafeTransaction({to: olas.address, data: callData[0], nonce: 0}),
                safeContracts.buildSafeTransaction({to: olas.address, data: callData[1], nonce: 0}),
                safeContracts.buildSafeTransaction({to: olas.address, data: callData[2], nonce: 0})];
            let safeTx = safeContracts.buildMultiSendSafeTx(multiSend, txs, nonce);
            await expect(
                // executeTxWithSigners() essentially calls the following steps for signing the batch of transactions
                // safe == CM, signers == safeSignersCM, tx == safeTx
                //    const sigs = await Promise.all(signers.map((signer) => exports.safeSignTypedData(signer, safe, tx)));
                //    return:
                //        signer: signerAddress,
                //        data: await signer._signTypedData({ verifyingContract: safe.address, chainId: cid }, exports.EIP712_SAFE_TX_TYPE, safeTx)
                safeContracts.executeTxWithSigners(CM, safeTx, safeSignersCM)
            ).to.emit(CM, "ExecutionSuccess");

            // Check the balance of contracts to be 500 million in total
            const balanceTimelock = BigInt(await olas.balanceOf(timelock.address));
            const balanceSale = BigInt(await olas.balanceOf(sale.address));
            const balanceValory = BigInt(await olas.balanceOf(valoryMultisig.address));
            const sumBalance = balanceTimelock + balanceSale + balanceValory;
            expect(sumBalance).to.equal(BigInt(initSupply));
            // End of 15: EOA is the owner of: factory
            //            EOA is the admin of timelock
            //            CM is the owner of: OLAS, buOLAS, sale
            //            CM is the minter of: OLAS
            //            CM is the proposer, canceller and executor of timelock
            //            timelock is the admin of timelock
            //            timelock is the governance of governor
            //            governor is the admin, proposer, canceller and executor of timelock
            //            Balances in OLAS: timelock: 100 million, sale: 301.5 million, valory multisig: 125 million

            // 16. CM to send transaction to Sale contract (`createBalancesFor()`) to create balances for initial DAO members
            // for them to claim and lock later with veOLAS and buOLAS;
            // Read the data from JSON file
            const dataFromJSON = fs.readFileSync(jsonFile, "utf8");
            const parsedData = JSON.parse(dataFromJSON);
            // Get veOLAS-related set of arrays
            const veOLASData = parsedData["veOLAS"];
            // Get buOLAS-related set of arrays
            const buOLASData = parsedData["buOLAS"];
            nonce = await CM.nonce();
            let txHashData = await safeContracts.buildContractCall(sale, "createBalancesFor",
                [veOLASData["addresses"], veOLASData["amounts"], veOLASData["lockTimes"],
                    buOLASData["addresses"], buOLASData["amounts"], buOLASData["numSteps"]],
                nonce, 0, 0);
            await signAndExecuteSafeTx(CM, txHashData);

            // Check veOLAS and buOLAS for the claimable addresses
            for (let i = 0; i < veOLASData["addresses"].length; i++) {
                const balances = await sale.claimableBalances(veOLASData["addresses"][i]);
                expect(balances.veBalance).to.equal(veOLASData["amounts"][i]);
            }

            for (let i = 0; i < buOLASData["addresses"].length; i++) {
                const balances = await sale.claimableBalances(buOLASData["addresses"][i]);
                expect(balances.buBalance).to.equal(buOLASData["amounts"][i]);
            }
            // End of 16: EOA is the owner of: factory
            //            EOA is the admin of timelock
            //            CM is the owner of: OLAS, buOLAS, sale
            //            CM is the minter of: OLAS
            //            CM is the proposer, canceller and executor of timelock
            //            timelock is the admin of timelock
            //            timelock is the governance of governor
            //            governor is the admin, proposer, canceller and executor of timelock
            //            Balances in OLAS: timelock: 100 million, sale: 301.5 million, valory multisig: 125 million

            // 17. CM to transfer its minting and its owner rights to Timelock with CM calling `changeMinter(Timelock)` and `changeOwner(Timelock)`;
            // 18. CM to transfer ownership rights of buOLAS to Timelock calling `changeOwner(Timelock)`;
            // 19. CM to transfer ownership rights of Sale to Timelock calling `changeOwner(Timelock)`;
            nonce = await CM.nonce();
            callData = [olas.interface.encodeFunctionData("changeMinter", [timelock.address]),
                olas.interface.encodeFunctionData("changeOwner", [timelock.address]),
                bu.interface.encodeFunctionData("changeOwner", [timelock.address]),
                sale.interface.encodeFunctionData("changeOwner", [valoryMultisig.address])];
            txs = [safeContracts.buildSafeTransaction({to: olas.address, data: callData[0], nonce: 0}),
                safeContracts.buildSafeTransaction({to: olas.address, data: callData[1], nonce: 0}),
                safeContracts.buildSafeTransaction({to: bu.address, data: callData[2], nonce: 0}),
                safeContracts.buildSafeTransaction({to: sale.address, data: callData[3], nonce: 0})];
            safeTx = safeContracts.buildMultiSendSafeTx(multiSend, txs, nonce);
            await expect(
                safeContracts.executeTxWithSigners(CM, safeTx, safeSignersCM)
            ).to.emit(CM, "ExecutionSuccess");

            // Try to change owner of OLAS by CM once again
            nonce = await CM.nonce();
            txHashData = await safeContracts.buildContractCall(olas, "changeOwner", [CM.address], nonce, 0, 0);
            // Safe returns GS013 on unsuccessful transaction
            await expect(
                signAndExecuteSafeTx(CM, txHashData)
            ).to.be.revertedWith("GS013");

            // Try to change owner of buOLAS by CM once again
            nonce = await CM.nonce();
            txHashData = await safeContracts.buildContractCall(bu, "changeOwner", [CM.address], nonce, 0, 0);
            // Safe returns GS013 on unsuccessful transaction
            await expect(
                signAndExecuteSafeTx(CM, txHashData)
            ).to.be.revertedWith("GS013");

            // Try to change owner of Sale by CM once again
            nonce = await CM.nonce();
            txHashData = await safeContracts.buildContractCall(sale, "changeOwner", [CM.address], nonce, 0, 0);
            // Safe returns GS013 on unsuccessful transaction
            await expect(
                signAndExecuteSafeTx(CM, txHashData)
            ).to.be.revertedWith("GS013");
            // End of 19: EOA is the owner of: factory
            //            EOA is the admin of timelock
            //            CM is the proposer, canceller and executor of timelock
            //            timelock is the owner of: OLAS, buOLAS, sale
            //            timelock is the minter of: OLAS
            //            timelock is the admin of timelock
            //            timelock is the governance of governor
            //            governor is the admin, proposer, canceller and executor of timelock
            //            Balances in OLAS: timelock: 100 million, sale: 301.5 million, valory multisig: 125 million

            // 20. EOA to revoke self admin rights from the Timelock (via `renounceRole()`);
            await timelock.connect(EOA).renounceRole(adminRole, EOA.address);

            // Verify EOA address roles to be all revoked
            await checkTimelockRoles(timelock, EOA.address, [false, false, false, false]);
            // End of 20: EOA is the owner of: factory
            //            CM is the proposer, canceller and executor of timelock
            //            timelock is the owner of: OLAS, buOLAS, sale
            //            timelock is the minter of: OLAS
            //            timelock is the admin of timelock
            //            timelock is the governance of governor
            //            governor is the admin, proposer, canceller and executor of timelock
            //            Balances in OLAS: timelock: 100 million, sale: 301.5 million, valory multisig: 125 million

            // 21. EOA to revoke self ownership rights from deployFactory to Null Address (via `changeOwner()`)
            await factory.connect(EOA).changeOwner("0x000000000000000000000000000000000000dEaD");
            await expect(
                factory.connect(EOA).changeOwner(EOA.address)
            ).to.be.revertedWith("OwnerOnly");
            // End of 21:
            //            CM is the proposer, canceller and executor of timelock
            //            timelock is the owner of: OLAS, buOLAS, sale
            //            timelock is the minter of: OLAS
            //            timelock is the admin of timelock
            //            timelock is the governance of governor
            //            governor is the admin, proposer, canceller and executor of timelock
            //            Balances in OLAS: timelock: 100 million, sale: 0 if all claimed, valory multisig: 125 million
            //            Balances in veOLAS: from sale claimable for veOLAS
            //            Balances in buOLAS: from sale claimable for buOLAS

            // 21+ Test the possibility to claim issued balances by the claimable accounts
            for (let i = 0; i < veOLASSigners.length; i++) {
                await sale.connect(veOLASSigners[i]).claim();
                const balance = await ve.balanceOf(veOLASSigners[i].address);
                expect(balance).to.equal(veOLASData["amounts"][i]);
            }

            // Those that were claimed during the veOLAS should not be claimed now
            for (let i = 0; i < buOLASSigners.length; i++) {
                if (!veOLASSigners.includes(buOLASSigners[i])) {
                    await sale.connect(buOLASSigners[i]).claim();
                }
                const balance = await bu.balanceOf(buOLASSigners[i].address);
                expect(balance).to.equal(buOLASData["amounts"][i]);
            }
            // End of deployment: same as End of 21
        });
    });
});
