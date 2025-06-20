/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);

    const signers = await ethers.getSigners();

    // EOA address
    const EOA = signers[0];

    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    // Wormhole Messenger address on Celo (from scripts/deployment/bridges/wormhole/deprecated_globals_celo_mainnet.json)
    const wormholeMessengerAddress = "0x397125902ED2cA2d42104F621f448A2cE1bC8Fb7";
    const wormholeL1MessageRelayerAddress = parsedData.wormholeL1MessageRelayerAddress;

    // WormholeRelayer contract
    const wormholeRelayerJSON = "abis/test/WormholeRelayer.json";
    const contractFromJSON = fs.readFileSync(wormholeRelayerJSON, "utf8");
    const wormholeRelayerABI = JSON.parse(contractFromJSON);
    const wormholeRelayer = await ethers.getContractAt(wormholeRelayerABI, wormholeL1MessageRelayerAddress);

    const WormholeMessenger = await ethers.getContractFactory("WormholeMessenger");

    let wormholeRelayerTimelockAddress = parsedData.wormholeRelayerTimelockAddress;
    // TODO Delete next line when wormholeRelayerTimelock is deployed
    wormholeRelayerTimelockAddress = deployer;
    const rawPayload = WormholeMessenger.interface.encodeFunctionData("changeSourceGovernor",
        ["0x" + "0".repeat(24) + wormholeRelayerTimelockAddress.slice(2)]);

    // Pack the data into one contiguous buffer
    const target = wormholeMessengerAddress;
    const value = 0;
    const payload = ethers.utils.arrayify(rawPayload);
    const data = ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    );

    // Celo chain Id
    const targetChain = 14;
    // Gas limit on Celo: 2M
    const minGasLimit = 2000000;
    // Get quote
    const quote = await wormholeRelayer["quoteEVMDeliveryPrice(uint16,uint256,uint256)"](targetChain, 0, minGasLimit);

    // Proposal preparation
    console.log("Change Source Governor on Celo");
    // Build the final payload to be called by the Timelock
    // sendPayloadToEvm selector with refund address
    const sendPayloadSelector = "0x4b5ca6f4";
    const timelockPayload = wormholeRelayer.interface.encodeFunctionData(sendPayloadSelector, [targetChain,
        wormholeMessengerAddress, data, 0, minGasLimit, targetChain, wormholeMessengerAddress]);

    // Proposal details
    console.log("Target:", wormholeL1MessageRelayerAddress);
    console.log("Value:", quote.nativePriceQuote.toString());
    console.log("Timelock payload for schedule and execute:", timelockPayload);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
