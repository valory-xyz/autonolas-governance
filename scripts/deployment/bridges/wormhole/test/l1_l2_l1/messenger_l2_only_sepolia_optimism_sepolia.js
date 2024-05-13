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
    // WormholeRelayer address on optimistic sepolia
    const wormholeRelayerAddress = "0x93BAD53DDfB6132b0aC8E37f6029163E63372cEE";
    const wormholeRelayerJSON = "abis/test/WormholeRelayer.json";
    let contractFromJSON = fs.readFileSync(wormholeRelayerJSON, "utf8");
    const wormholeRelayerABI = JSON.parse(contractFromJSON);
    const wormholeRelayer = new ethers.Contract(wormholeRelayerAddress, wormholeRelayerABI, optimisticSepoliaProvider);

    // Test deployed WormholeMessenger address on optimisticSepolia
    const wormholeMessengerAddress = "0x04A0afD079F14D539B17253Ea93563934A024165"; // payable process on L2
    const wormholeMessengerJSON = "artifacts/contracts/bridges/test/WormholeL2ReceiverL1Sender.sol/WormholeL2ReceiverL1Sender.json";
    contractFromJSON = fs.readFileSync(wormholeMessengerJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const wormholeMessengerABI = parsedFile["abi"];
    const wormholeMessenger = new ethers.Contract(wormholeMessengerAddress, wormholeMessengerABI, optimisticSepoliaProvider);

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAsepolia = new ethers.Wallet(account, sepoliaProvider);
    const EOAoptimisticSepolia = new ethers.Wallet(account, optimisticSepoliaProvider);
    console.log("EOA address",EOAsepolia.address);
    if (EOAoptimisticSepolia.address == EOAsepolia.address) {
        console.log("Correct wallet setup");
    }

    const targetChain = 10002; // sepolia
    const minGasLimit = "50000";
    const transferCost = await wormholeRelayer["quoteEVMDeliveryPrice(uint16,uint256,uint256)"](targetChain, 0, minGasLimit);

    // Send the message to optimisticSepolia receiver
    const tx = await wormholeMessenger.connect(EOAoptimisticSepolia).sendMessage({ value: transferCost.nativePriceQuote });
    console.log("Execution hash", tx.hash);
    await tx.wait();
    // https://wormholescan.io/#/tx/0xef934da740738881b3069373602a64148944e15ae3b5da2c2630f85886ae6453?network=TESTNET
    // https://sepolia.etherscan.io/tx/0x3c85e931ee7f974f771d2b589a11f24e6982f4d68444e47ff57f6a24203788b0
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
