/*global process*/

const { ethers } = require("ethers");

const sendFundsFromL1 = false;

async function main() {
    const sepoliaURL = "https://eth-sepolia.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_SEPOLIA;
    const sepoliaProvider = new ethers.providers.JsonRpcProvider(sepoliaURL);
    await sepoliaProvider.getBlockNumber().then((result) => {
        console.log("Current block number sepolia: " + result);
    });

    const polygonMumbaiURL = "https://polygon-mumbai.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MUMBAI;
    const polygonMumbaiProvider = new ethers.providers.JsonRpcProvider(polygonMumbaiURL);
    await polygonMumbaiProvider.getBlockNumber().then((result) => {
        console.log("Current block number polygonMumbai: " + result);
    });

    const fs = require("fs");
    // WormholeRelayer address on sepolia
    const wormholeRelayerAddress = "0x7B1bD7a6b4E61c2a123AC6BC2cbfC614437D0470";
    const wormholeRelayerJSON = "abis/test/WormholeRelayer.json";
    let contractFromJSON = fs.readFileSync(wormholeRelayerJSON, "utf8");
    const wormholeRelayerABI = JSON.parse(contractFromJSON);
    const wormholeRelayer = new ethers.Contract(wormholeRelayerAddress, wormholeRelayerABI, sepoliaProvider);

    // Test deployed WormholeMessenger address on polygonMumbai
    const wormholeMessengerAddress = "0x32837288823fA6a35BD3a2A3a5DB6770b50690a4"; // payable process on L2
    const wormholeMessengerJSON = "artifacts/contracts/bridges/WormholeMessenger.sol/WormholeMessenger.json";
    contractFromJSON = fs.readFileSync(wormholeMessengerJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const wormholeMessengerABI = parsedFile["abi"];
    const wormholeMessenger = new ethers.Contract(wormholeMessengerAddress, wormholeMessengerABI, polygonMumbaiProvider);

    // Mock Timelock contract address on sepolia (has WormholeRelayer address in it already)
    const mockTimelockAddress = "0x14CF2e543AB75B321bcf84C3AcC88d570Ccf9106"; // payable
    const mockTimelockJSON = "artifacts/contracts/bridges/test/MockTimelock.sol/MockTimelock.json";
    contractFromJSON = fs.readFileSync(mockTimelockJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const mockTimelockABI = parsedFile["abi"];
    const mockTimelock = new ethers.Contract(mockTimelockAddress, mockTimelockABI, sepoliaProvider);

    // ChildMockERC20 address on polygonMumbai
    const mockChildERC20Address = "0x724bE493CeC72003C6941A9f4186dc2c45392315";
    const mockChildERC20JSON = "artifacts/contracts/bridges/test/ChildMockERC20.sol/ChildMockERC20.json";
    contractFromJSON = fs.readFileSync(mockChildERC20JSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const mockChildERC20ABI = parsedFile["abi"];
    const mockChildERC20 = new ethers.Contract(mockChildERC20Address, mockChildERC20ABI, polygonMumbaiProvider);

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAsepolia = new ethers.Wallet(account, sepoliaProvider);
    const EOApolygonMumbai = new ethers.Wallet(account, polygonMumbaiProvider);
    console.log("EOA address",EOAsepolia.address);
    if (EOApolygonMumbai.address == EOAsepolia.address) {
        console.log("Correct wallet setup");
    }

    // Amount of CELO to send
    const amountToSend = ethers.utils.parseEther("0.0001");
    // Amount of ERC20 token to mint
    const amountToMint = 100;

    // Send funds to the WormholeMessenger contract
    let tx;
    if (!sendFundsFromL1) {
        // Feed the contract with funds on the L2 side
        tx = await EOApolygonMumbai.sendTransaction({to: wormholeMessenger.address, value: amountToSend});
        console.log("Send CELO hash", tx.hash);
        await tx.wait();
    }

    // Pack the first part of  with the zero payload
    let target = EOApolygonMumbai.address;
    let value = amountToSend;
    const payloadLength = 0;
    let data = ethers.utils.solidityPack(
        ["address", "uint96", "uint32"],
        [target, value, payloadLength]
    );

    const targetChain = 5; // polygon
    const minGasLimit = "2000000";
    const transferCost = await wormholeRelayer["quoteEVMDeliveryPrice(uint16,uint256,uint256)"](targetChain, 0, minGasLimit);

    // Mock Token contract across the bridge must mint 100 OLAS for the deployer
    const rawPayload = mockChildERC20.interface.encodeFunctionData("mint", [EOApolygonMumbai.address, amountToMint]);
    // Pack the second part of data
    target = mockChildERC20Address;
    value = 0;
    const payload = ethers.utils.arrayify(rawPayload);
    data += ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    ).slice(2);

    // Balance of mock tokens before the cross-bridge transaction
    const balanceERC20Before = Number(await mockChildERC20.balanceOf(EOApolygonMumbai.address));
    // Balance of CELO of the WormholeMessenger before the cross-bridge transaction
    const balanceETHBefore = await polygonMumbaiProvider.getBalance(EOApolygonMumbai.address);

    // Build the final payload to be passed from the imaginary Timelock
    const sendPayloadSelector = "0x4b5ca6f4";
    const timelockPayload = await wormholeRelayer.interface.encodeFunctionData(sendPayloadSelector, [targetChain,
        wormholeMessengerAddress, data, 0, minGasLimit, targetChain, wormholeMessengerAddress]);

    // Send the message to polygonMumbai receiver
    tx = await mockTimelock.connect(EOAsepolia).execute(timelockPayload, { value: transferCost.nativePriceQuote });
    console.log("Timelock data execution hash", tx.hash);
    await tx.wait();

    // Wait for the event of a processed data on polygonMumbai
    // catch NewFxMessage event from mockChildERC20 and MessageReceived event from wormholeMessenger
    // Compare the data sent and the data from the NewFxMessage event that must match
    // MessageReceived(uint256 indexed stateId, address indexed sender, bytes message)
    let waitForEvent = true;
    while (waitForEvent) {
        // Check for the last 100 blocks in order to catch the event
        const events = await wormholeMessenger.queryFilter("MessageReceived", -200);
        events.forEach((item) => {
            const msg = item["args"]["data"];
            if (msg == data) {
                console.log("Event MessageReceived. Message in polygonMumbai:", msg);
                waitForEvent = false;
            }
        });
        // Continue waiting for the event if none was received
        if (waitForEvent) {
            console.log("Waiting for the receive event, next update in 5 minutes ...");
            // Sleep for a minute
            await new Promise(r => setTimeout(r, 300000));
        }
    }

    // Balance of ERC20 token after the cross-bridge transaction
    const balanceERC20After = Number(await mockChildERC20.balanceOf(EOApolygonMumbai.address));
    const balanceERC20Diff = balanceERC20After - balanceERC20Before;
    if (balanceERC20Diff == amountToMint) {
        console.log("Successfully minted MockChildERC20");
    }

    // Balance of CELO of the WormholeMessenger after the cross-bridge transaction
    const balanceETHAfter = await polygonMumbaiProvider.getBalance(EOApolygonMumbai.address);
    const balanceETHDiff = balanceETHAfter - balanceETHBefore;
    if (balanceETHDiff == amountToSend) {
        console.log("Successfully sent CELO");
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
