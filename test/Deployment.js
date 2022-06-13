/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Deployment", function () {
    let signers;
    let EOA;
    let safeSigners;
    const safeThreshold = 3;
    let nonce =  0;
    const AddressZero = "0x" + "0".repeat(40);
    const adminRole = ethers.utils.id("TIMELOCK_ADMIN_ROLE");
    const proposerRole = ethers.utils.id("PROPOSER_ROLE");
    const executorRole = ethers.utils.id("EXECUTOR_ROLE");
    const cancellerRole = ethers.utils.id("CANCELLER_ROLE");
    let gnosisSafeL2;
    let gnosisSafeProxyFactory;

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

        signers = await ethers.getSigners();
        EOA = signers[0];
        safeSigners = [signers[1], signers[2], signers[3]];
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

    context("Deployment script testing", async function () {
        it("Following specified steps to deploy contracts", async function () {
            // 1. EOA creates community multisig (CM) of the DAO with Gnosis Safe, that has 3 signers and 3 threshold;
            const safeContracts = require("@gnosis.pm/safe-contracts");
            const setupData = gnosisSafeL2.interface.encodeFunctionData(
                "setup",
                // signers, threshold, to_address, data, fallback_handler, payment_token, payment, payment_receiver
                [[safeSigners[0].address, safeSigners[1].address, safeSigners[2].address], safeThreshold, AddressZero,
                    "0x", AddressZero, AddressZero, 0, AddressZero]
            );
            const proxyAddress = await safeContracts.calculateProxyAddress(gnosisSafeProxyFactory, gnosisSafeL2.address,
                setupData, nonce);
            await gnosisSafeProxyFactory.createProxyWithNonce(gnosisSafeL2.address, setupData, nonce).then((tx) => tx.wait());
            const CM = await ethers.getContractAt("GnosisSafeL2", proxyAddress);

            // 2. EOA to deploy deployFactory and get deployAddress of deployFactory;
            const FACTORY = await ethers.getContractFactory("DeploymentFactory");
            const factory = await FACTORY.connect(EOA).deploy();
            await factory.deployed();

            // 3. Brutforce salt for vanity address OLAS (deployAddress + bytecode);
            const olasSalt = bruteForceOLAS(factory.address);

            // 4. EOA to deploy OLAS contract via deployFactory (becoming its owner and minter);
            await factory.deployOLAS(olasSalt);
            const olasAddress = await factory.olasAddress();

            // 5. EOA changes owner and minter on OLAS contract to CM: call `changeMinter(CM)` and `changeOwner(CM)`;
            const olas = await ethers.getContractAt("OLAS", olasAddress);
            await olas.changeMinter(CM.address);
            await olas.changeOwner(CM.address);

            // Check that the owner can't be changed by the EOA now
            await expect(
                olas.connect(EOA).changeOwner(EOA.address)
            ).to.be.revertedWith("ManagerOnly");

            // 6. EOA to deploy the Timelock contract with the proposer ("PROPOSER_ROLE"), executor ("EXECUTOR_ROLE"),
            // and canceller ("CANCELLER_ROLE") roles given to the CM (via deployment with `proposers` and `executors` parameters being the CM address);
            const minDelay = 13091; // 2 days with 13.2s block
            const executors = [CM.address];
            const proposers = [CM.address];
            const Timelock = await ethers.getContractFactory("Timelock");
            const timelock = await Timelock.deploy(minDelay, proposers, executors);
            await timelock.deployed();

            // Verify CM address roles
            expect(await timelock.hasRole(adminRole, CM.address)).to.equal(false);
            expect(await timelock.hasRole(executorRole, CM.address)).to.equal(true);
            expect(await timelock.hasRole(proposerRole, CM.address)).to.equal(true);
            expect(await timelock.hasRole(cancellerRole, CM.address)).to.equal(true);

            // 7. Brutforce salt for vanity address veOLAS (deployAddress + OLAS address + bytecode);
            const veSalt = bruteForceVeOLAS(factory.address, olasAddress);

            // 8. EOA to deploy veOLAS contract via deployFactory pointed to OLAS;
            await factory.deployVeOLAS(veSalt, olas.address);
            const veOLASAddress = await factory.veOLASAddress();
            const ve = await ethers.getContractAt("veOLAS", veOLASAddress);

            // 9. EOA to deploy GovernorOLAS contract with veOLAS and Timelock addresses as input parameters
            // and other defined governor-related parameters;
            const initialVotingDelay = 13091; // 2 days with 13.2s block
            const initialVotingPeriod = 19636; // 3 days with 13.2s block
            const initialProposalThreshold = "1" + "0" * 21; // 1000 OLAS
            const quorum = 4;
            const GovernorOLAS = await ethers.getContractFactory("GovernorOLAS");
            const governor = await GovernorOLAS.deploy(ve.address, timelock.address, initialVotingDelay,
                initialVotingPeriod, initialProposalThreshold, quorum);
            await governor.deployed();

            // 10. EOA to give admin ("TIMELOCK_ADMIN_ROLE"), proposer ("PROPOSER_ROLE"), executor ("EXECUTOR_ROLE"),
            // and canceller ("CANCELLER_ROLE") roles to GovernorOLAS from Timelock (in separate transactions via `grantRole()` calls);
            await timelock.grantRole(adminRole, governor.address);
            await timelock.grantRole(executorRole, governor.address);
            await timelock.grantRole(proposerRole, governor.address);
            await timelock.grantRole(cancellerRole, governor.address);

            // Verify governor address roles
            expect(await timelock.hasRole(adminRole, governor.address)).to.equal(true);
            expect(await timelock.hasRole(executorRole, governor.address)).to.equal(true);
            expect(await timelock.hasRole(proposerRole, governor.address)).to.equal(true);
            expect(await timelock.hasRole(cancellerRole, governor.address)).to.equal(true);

            // 11. EOA to deploy buOLAS contract pointed to OLAS;
            const BU = await ethers.getContractFactory("buOLAS");
            const bu = await BU.deploy(olas.address, "Burnable Locked OLAS", "buOLAS");
            await bu.deployed();

            // 12. EOA changes owner on buOLAS to CM: call `changeOwner(CM)`;
            await bu.connect(EOA).changeOwner(CM.address);

            // Verify the ownership of buOLAS contract
            await expect(
                bu.connect(EOA).changeOwner(EOA.address)
            ).to.be.revertedWith("OwnerOnly");

            // 13. EOA to deploy Sale contract pointed to OLAS, veOLAs and bOLAS;
            const SALE = await ethers.getContractFactory("Sale");
            const sale = await SALE.deploy(olas.address, ve.address, bu.address);
            await sale.deployed();

            // 14. EOA changes the owner on Sale contract to CM: call `changeOwner(CM)`;
            await sale.connect(EOA).changeOwner(CM.address);

            // Verify the ownership of Sale contract
            await expect(
                sale.connect(EOA).changeOwner(EOA.address)
            ).to.be.revertedWith("OwnerOnly");

            // 15. CM to mint initial OLAS supply for DAO treasury (sent to Timelock), DAO members (sent to Sale contract),
            // Valory (sent to Valory multisig);
            const initSupply = "5" + "0".repeat(26);
            // Numbers below must accumulate to initSupply
            const timelockSupply = "2" + "0".repeat(26);
            const saleSupply = "2" + "0".repeat(26);
            const cmSupply = "1" + "0".repeat(26);
            // Mint for Timelock
            nonce = await CM.nonce();
            let txHashData = await safeContracts.buildContractCall(olas, "mint", [timelock.address, timelockSupply], nonce, 0, 0);
            let signMessageData = [await safeContracts.safeSignMessage(safeSigners[0], CM, txHashData, 0),
                await safeContracts.safeSignMessage(safeSigners[1], CM, txHashData, 0),
                await safeContracts.safeSignMessage(safeSigners[2], CM, txHashData, 0)];
            await safeContracts.executeTx(CM, txHashData, signMessageData, 0);
            // Mint for Sale
            nonce = await CM.nonce();
            txHashData = await safeContracts.buildContractCall(olas, "mint", [sale.address, saleSupply], nonce, 0, 0);
            signMessageData = [await safeContracts.safeSignMessage(safeSigners[0], CM, txHashData, 0),
                await safeContracts.safeSignMessage(safeSigners[1], CM, txHashData, 0),
                await safeContracts.safeSignMessage(safeSigners[2], CM, txHashData, 0)];
            await safeContracts.executeTx(CM, txHashData, signMessageData, 0);
            // Mint for CM
            nonce = await CM.nonce();
            txHashData = await safeContracts.buildContractCall(olas, "mint", [CM.address, cmSupply], nonce, 0, 0);
            signMessageData = [await safeContracts.safeSignMessage(safeSigners[0], CM, txHashData, 0),
                await safeContracts.safeSignMessage(safeSigners[1], CM, txHashData, 0),
                await safeContracts.safeSignMessage(safeSigners[2], CM, txHashData, 0)];
            await safeContracts.executeTx(CM, txHashData, signMessageData, 0);

            // Check the balance of contracts to be 500 million in total
            const balanceTimelock = BigInt(await olas.balanceOf(timelock.address));
            const balanceSale = BigInt(await olas.balanceOf(sale.address));
            const balanceCM = BigInt(await olas.balanceOf(CM.address));
            const sumBalance = balanceTimelock + balanceSale + balanceCM;
            expect(sumBalance).to.equal(BigInt(initSupply));

            // 16. CM to send transaction to Sale contract (`createBalancesFor()`) to create balances for initial DAO members
            // for them to claim and lock later with veOLAS and buOLAS;
            const account = signers[5];
            const thousandOLABalance = "1000" + "0".repeat(18);
            const oneYear = 365 * 86400;
            const numSteps = 4;
            // As an example, create lockable balances for the account in both veOLAS and buOLAS for 1k OLAS (2k total)
            nonce = await CM.nonce();
            txHashData = await safeContracts.buildContractCall(sale, "createBalancesFor",
                [[account.address], [thousandOLABalance], [oneYear],[account.address], [thousandOLABalance], [numSteps]],
                nonce, 0, 0);
            signMessageData = [await safeContracts.safeSignMessage(safeSigners[0], CM, txHashData, 0),
                await safeContracts.safeSignMessage(safeSigners[1], CM, txHashData, 0),
                await safeContracts.safeSignMessage(safeSigners[2], CM, txHashData, 0)];
            await safeContracts.executeTx(CM, txHashData, signMessageData, 0);

            // Check veOLAS and buOLAS for the account address
            const balances = await sale.claimableBalances(account.address);
            expect(balances.veBalance).to.equal(thousandOLABalance);
            expect(balances.buBalance).to.equal(thousandOLABalance);

            // 17. CM to transfer its minting rights to Timelock with CM calling `changeMinter(Timelock)`;
            nonce = await CM.nonce();
            txHashData = await safeContracts.buildContractCall(olas, "changeMinter", [timelock.address], nonce, 0, 0);
            signMessageData = [await safeContracts.safeSignMessage(safeSigners[0], CM, txHashData, 0),
                await safeContracts.safeSignMessage(safeSigners[1], CM, txHashData, 0),
                await safeContracts.safeSignMessage(safeSigners[2], CM, txHashData, 0)];
            await safeContracts.executeTx(CM, txHashData, signMessageData, 0);

            // 18. CM to transfer ownership rights of buOLAS to Timelock calling `changeOwner(Timelock)`;
            nonce = await CM.nonce();
            txHashData = await safeContracts.buildContractCall(olas, "changeOwner", [timelock.address], nonce, 0, 0);
            signMessageData = [await safeContracts.safeSignMessage(safeSigners[0], CM, txHashData, 0),
                await safeContracts.safeSignMessage(safeSigners[1], CM, txHashData, 0),
                await safeContracts.safeSignMessage(safeSigners[2], CM, txHashData, 0)];
            await safeContracts.executeTx(CM, txHashData, signMessageData, 0);

            // Try to change owner by CM once again
            nonce = await CM.nonce();
            txHashData = await safeContracts.buildContractCall(olas, "changeOwner", [CM.address], nonce, 0, 0);
            signMessageData = [await safeContracts.safeSignMessage(safeSigners[0], CM, txHashData, 0),
                await safeContracts.safeSignMessage(safeSigners[1], CM, txHashData, 0),
                await safeContracts.safeSignMessage(safeSigners[2], CM, txHashData, 0)];
            // Safe returns GS013 on unsuccessful transaction
            await expect(
                safeContracts.executeTx(CM, txHashData, signMessageData, 0)
            ).to.be.revertedWith("GS013");

            // 19. EOA to revoke self admin rights from the Timelock (via `renounceRole()`);
            await timelock.connect(EOA).renounceRole(adminRole, EOA.address);

            // Verify EOA address roles
            expect(await timelock.hasRole(adminRole, EOA.address)).to.equal(false);
            expect(await timelock.hasRole(executorRole, EOA.address)).to.equal(false);
            expect(await timelock.hasRole(proposerRole, EOA.address)).to.equal(false);
            expect(await timelock.hasRole(cancellerRole, EOA.address)).to.equal(false);

            // 20+ Test the possibility to claim issued balances by the account
            await sale.connect(account).claim();
            let balance = await ve.balanceOf(account.address);
            expect(balance).to.equal(thousandOLABalance);
            balance = await bu.balanceOf(account.address);
            expect(balance).to.equal(thousandOLABalance);
        });
    });
});
