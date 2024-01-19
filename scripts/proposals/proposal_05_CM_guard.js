const { ethers } = require("hardhat");
const safeContracts = require("@gnosis.pm/safe-contracts");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");

    const signers = await ethers.getSigners();
    const safeThreshold = 7;
    const AddressZero = "0x" + "0".repeat(40);

    // Deploy Safe multisig
    const safeSigners = signers.slice(1, 10).map(currentElement => currentElement.address);

    const GnosisSafe = await ethers.getContractFactory("GnosisSafe");
    const gnosisSafe = await GnosisSafe.deploy();
    await gnosisSafe.deployed();

    const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
    const gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
    await gnosisSafeProxyFactory.deployed();

    // Create a multisig that will be the service owner
    const setupData = gnosisSafe.interface.encodeFunctionData(
        "setup",
        [safeSigners, safeThreshold, AddressZero, "0x", AddressZero, AddressZero, 0, AddressZero]
    );
    const proxyAddress = await safeContracts.calculateProxyAddress(gnosisSafeProxyFactory, gnosisSafe.address, setupData, 0);
    await gnosisSafeProxyFactory.createProxyWithNonce(gnosisSafe.address, setupData, 0).then(tx => tx.wait());

    // Get the multisig
    const multisig = await ethers.getContractAt("GnosisSafe", proxyAddress);
    const nonce = await multisig.nonce();

    const parsedData = JSON.parse(dataFromJSON);

    const timelockAddress = parsedData.timelockAddress;
    const guardCMAddress = parsedData.guardCMAddress;

    
    // Manually set gas limit and gas price
    const gasLimit = 500000;  // Adjust this value based on your needs
    const gasPrice = ethers.utils.parseUnits("50", "gwei");  // Adjust this value based on current gas prices


    // Construct the payload for the multisig to swap the guard by the Timelock
    const txHashData = await safeContracts.buildContractCall(multisig, "setGuard", [guardCMAddress], nonce, 0, 0);
    parsedData.CM
    console.log("Set new guard via Timelock Module");

    const targets = [guardCMAddress];
    const values = new Array(1).fill(0);
    const callDatas = [
        multisig.interface.encodeFunctionData("execTransactionFromModule", [txHashData.to, 0, txHashData.data, txHashData.operation])
    ];
    const description = "Timelock to change guard via module and select selects";

    // Proposal details
    console.log("targets:", targets);
    console.log("values:", values);
    console.log("call datas:", callDatas);
    console.log("description:", description);

    // Send the transaction with manually set gas limit and gas price
    const tx = await multisig.submitTransaction(targets, values, callDatas, 0, description, { gasLimit, gasPrice });
    await tx.wait();

    console.log("Transaction successful");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
