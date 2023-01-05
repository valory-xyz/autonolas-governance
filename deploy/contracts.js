/*global ethers*/

module.exports = async () => {
    // Common parameters
    const AddressZero = "0x" + "0".repeat(40);
    // Initial OLAS supply of 1 million
    const initialMint = "1" + "0".repeat(24);
    // Lock-related parameters
    const oneYear = 365 * 86400;
    const numSteps = 4;

    // Governance related
    const minDelay = 1;
    const initialVotingDelay = 1; // blocks
    const initialVotingPeriod = 45818; // blocks ±= 1 week
    const initialProposalThreshold = 0; // voting power
    const quorum = 1; // quorum factor

    const signers = await ethers.getSigners();
    const deployer = signers[0];

    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());

    // Deploying governance contracts
    // Deploy OLAS token and veOLAS
    const OLAS = await ethers.getContractFactory("OLAS");
    const olas = await OLAS.deploy();
    await olas.deployed();
    console.log("OLAS token deployed to", olas.address);

    const VE = await ethers.getContractFactory("veOLAS");
    const ve = await VE.deploy(olas.address, "Voting Escrow OLAS", "veOLAS");
    await ve.deployed();
    console.log("Voting Escrow OLAS deployed to", ve.address);

    // Deploy timelock with a multisig being a proposer
    const executors = [];
    const proposers = [deployer.address];
    const Timelock = await ethers.getContractFactory("Timelock");
    const timelock = await Timelock.deploy(minDelay, proposers, executors);
    await timelock.deployed();
    console.log("Timelock deployed to", timelock.address);

    // Deploy Governor OLAS
    const GovernorOLAS = await ethers.getContractFactory("GovernorOLAS");
    const governor = await GovernorOLAS.deploy(ve.address, timelock.address, initialVotingDelay,
        initialVotingPeriod, initialProposalThreshold, quorum);
    await governor.deployed();
    console.log("Governor OLAS deployed to", governor.address);

    // Give the admin role to the governor as well
    const adminRole = ethers.utils.id("TIMELOCK_ADMIN_ROLE");
    await timelock.connect(deployer).grantRole(adminRole, governor.address);

    // Deploy buOLAS contract
    const BU = await ethers.getContractFactory("buOLAS");
    const bu = await BU.deploy(olas.address, "Lockable OLAS", "buOLAS");
    await bu.deployed();
    console.log("buOLAS deployed to", bu.address);

    // Mint the initial OLAS supply for the deployer contract
    await olas.mint(deployer.address, initialMint);
    console.log("Minted OLAS for deployer account:", initialMint);

    // Writing the JSON with the initial deployment data
    let initDeployJSON = {
        "OLAS": olas.address,
        "veOLAS": ve.address,
        "timelock": timelock.address,
        "GovernorOLA": governor.address,
        "buOLAS": bu.address,
    };

    // Write the json file with the setup
    let fs = require("fs");
    fs.writeFileSync("initDeploy.json", JSON.stringify(initDeployJSON));
};
