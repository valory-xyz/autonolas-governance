/*global process*/

const { ethers } = require("ethers");

async function main() {
    const sepoliaURL = "https://eth-sepolia.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_SEPOLIA;
    const sepoliaProvider = new ethers.providers.JsonRpcProvider(sepoliaURL);
    await sepoliaProvider.getBlockNumber().then((result) => {
        console.log("Current block number sepolia: " + result);
    });

    const optimisticSepoliaURL = "https://sepolia.optimism.io";
    const optimisticSepoliaProvider = new ethers.providers.JsonRpcProvider(optimisticSepoliaURL);
    await optimisticSepoliaProvider.getBlockNumber().then((result) => {
        console.log("Current block number optimisticSepolia: " + result);
    });

    const fs = require("fs");
    // WormholeRelayer address on sepolia
    const wormholeRelayerAddress = "0x7B1bD7a6b4E61c2a123AC6BC2cbfC614437D0470";
    const wormholeRelayerJSON = "abis/test/WormholeRelayer.json";
    let contractFromJSON = fs.readFileSync(wormholeRelayerJSON, "utf8");
    const wormholeRelayerABI = JSON.parse(contractFromJSON);
    const wormholeRelayer = new ethers.Contract(wormholeRelayerAddress, wormholeRelayerABI, sepoliaProvider);

    // Test deployed WormholeMessenger address on optimisticSepolia
    const wormholeMessengerAddress = "0x1d333b46dB6e8FFd271b6C2D2B254868BD9A2dbd"; // payable process on L2
    const wormholeMessengerJSON = "artifacts/contracts/bridges/test/WormholeL2ReceiverL1Sender.sol/WormholeL2ReceiverL1Sender.json";
    contractFromJSON = fs.readFileSync(wormholeMessengerJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const wormholeMessengerABI = parsedFile["abi"];
    const wormholeMessenger = new ethers.Contract(wormholeMessengerAddress, wormholeMessengerABI, optimisticSepoliaProvider);

    // Mock Timelock contract address on sepolia (has WormholeRelayer address in it already)
    const mockTimelockAddress = "0x14CF2e543AB75B321bcf84C3AcC88d570Ccf9106"; // payable
    const mockTimelockJSON = "artifacts/contracts/bridges/test/MockTimelock.sol/MockTimelock.json";
    contractFromJSON = fs.readFileSync(mockTimelockJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const mockTimelockABI = parsedFile["abi"];
    const mockTimelock = new ethers.Contract(mockTimelockAddress, mockTimelockABI, sepoliaProvider);

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAsepolia = new ethers.Wallet(account, sepoliaProvider);
    const EOAoptimisticSepolia = new ethers.Wallet(account, optimisticSepoliaProvider);
    console.log("EOA address",EOAsepolia.address);
    if (EOAoptimisticSepolia.address == EOAsepolia.address) {
        console.log("Correct wallet setup");
    }

    const amountToSend = ethers.utils.parseEther("0.02");
    let tx = await EOAoptimisticSepolia.sendTransaction({to: wormholeMessenger.address, value: amountToSend});
    console.log("Send Optimistic hash", tx.hash);
    await tx.wait();

    const targetChain = 10005; // optimistic sepolia
    const minGasLimit = "2000000";
    const transferCost = await wormholeRelayer["quoteEVMDeliveryPrice(uint16,uint256,uint256)"](targetChain, 0, minGasLimit);

    // Data = WormholeL1Receiver address in the bytes32 format
    const data = "0x000000000000000000000000f66e23209074fa7946e41f45f43d765281af2207";

    // Build the final payload to be passed from the imaginary Timelock
    const sendPayloadSelector = "0x4b5ca6f4";
    const timelockPayload = await wormholeRelayer.interface.encodeFunctionData(sendPayloadSelector, [targetChain,
        wormholeMessengerAddress, data, 0, minGasLimit, targetChain, wormholeMessengerAddress]);

    // Send the message to optimisticSepolia receiver
    tx = await mockTimelock.connect(EOAsepolia).execute(timelockPayload, { value: transferCost.nativePriceQuote });
    console.log("Timelock data execution hash", tx.hash);
    await tx.wait();
    // https://wormholescan.io/#/tx/0x2a7daee399681fd37e066c2672e06f1c43ff3dbdad4c8cbbc941a00529e7ae10?network=TESTNET
    // https://sepolia-optimism.etherscan.io/tx/0x31395dfd37e4095177e0d5a8ebbff0ebdcf30e8ee7e617078cf8677cec8ed24c
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
