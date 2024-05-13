/*global process*/

const { ethers } = require("ethers");

const sendFundsFromL1 = true;

async function main() {
    const ALCHEMY_API_KEY_SEPOLIA = process.env.ALCHEMY_API_KEY_SEPOLIA;
    const sepoliaURL = "https://eth-sepolia.g.alchemy.com/v2/" + ALCHEMY_API_KEY_SEPOLIA;
    const sepoliaProvider = new ethers.providers.JsonRpcProvider(sepoliaURL);
    await sepoliaProvider.getBlockNumber().then((result) => {
        console.log("Current block number sepolia: " + result);
    });

    const baseSepoliaURL = "https://sepolia.base.org";
    const baseSepoliaProvider = new ethers.providers.JsonRpcProvider(baseSepoliaURL);
    await baseSepoliaProvider.getBlockNumber().then((result) => {
        console.log("Current block number baseSepolia: " + result);
    });

    const fs = require("fs");
    // CDMProxy address on sepolia
    const CDMProxyAddress = "0xC34855F4De64F1840e5686e64278da901e261f20";
    const CDMProxyJSON = "abis/test/L1CrossDomainMessenger.json";
    let contractFromJSON = fs.readFileSync(CDMProxyJSON, "utf8");
    const CDMProxyABI = JSON.parse(contractFromJSON);
    const CDMProxy = new ethers.Contract(CDMProxyAddress, CDMProxyABI, sepoliaProvider);

    // Test deployed OptimismMessenger address on baseSepolia
    const optimismMessengerAddress = "0x6f7661F52fE1919996d0A4F68D09B344093a349d"; // payable process on L2
    const optimismMessengerJSON = "artifacts/contracts/bridges/OptimismMessenger.sol/OptimismMessenger.json";
    contractFromJSON = fs.readFileSync(optimismMessengerJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const optimismMessengerABI = parsedFile["abi"];
    const optimismMessenger = new ethers.Contract(optimismMessengerAddress, optimismMessengerABI, baseSepoliaProvider);

    // Mock Timelock contract address on sepolia (has CDMProxy address in it already)
    const mockTimelockAddress = "0x04A0afD079F14D539B17253Ea93563934A024165"; // payable
    const mockTimelockJSON = "artifacts/contracts/bridges/test/MockTimelock.sol/MockTimelock.json";
    contractFromJSON = fs.readFileSync(mockTimelockJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const mockTimelockABI = parsedFile["abi"];
    const mockTimelock = new ethers.Contract(mockTimelockAddress, mockTimelockABI, sepoliaProvider);

    // ChildMockERC20 address on baseSepolia
    const mockChildERC20Address = "0xc2c7E40674f1C7Bb99eFe5680Efd79842502bED4";
    const mockChildERC20JSON = "artifacts/contracts/bridges/test/ChildMockERC20.sol/ChildMockERC20.json";
    contractFromJSON = fs.readFileSync(mockChildERC20JSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const mockChildERC20ABI = parsedFile["abi"];
    const mockChildERC20 = new ethers.Contract(mockChildERC20Address, mockChildERC20ABI, baseSepoliaProvider);

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAsepolia = new ethers.Wallet(account, sepoliaProvider);
    const EOAbaseSepolia = new ethers.Wallet(account, baseSepoliaProvider);
    console.log("EOA address",EOAsepolia.address);
    if (EOAbaseSepolia.address == EOAsepolia.address) {
        console.log("Correct wallet setup");
    }

    // Amount of xETH to send
    const amountToSend = ethers.utils.parseEther("0.0001");
    // Amount of ERC20 token to mint
    const amountToMint = 100;

    // Send funds to the OptimismMessenger contract
    let tx;
    if (!sendFundsFromL1) {
        // Feed the contract with funds on the L2 side
        tx = await EOAbaseSepolia.sendTransaction({to: optimismMessenger.address, value: amountToSend});
        console.log("Send xETH hash", tx.hash);
        await tx.wait();
    }

    // Pack the first part of  with the zero payload
    let target = EOAbaseSepolia.address;
    let value = amountToSend;
    const payloadLength = 0;
    let data = ethers.utils.solidityPack(
        ["address", "uint96", "uint32"],
        [target, value, payloadLength]
    );

    // Mock Token contract across the bridge must mint 100 OLAS for the deployer
    const rawPayload = mockChildERC20.interface.encodeFunctionData("mint", [EOAbaseSepolia.address, amountToMint]);
    // Pack the second part of data
    target = mockChildERC20Address;
    value = 0;
    const payload = ethers.utils.arrayify(rawPayload);
    data += ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    ).slice(2);

    // Balance of mock tokens before the cross-bridge transaction
    const balanceERC20Before = Number(await mockChildERC20.balanceOf(EOAbaseSepolia.address));
    // Balance of xETH of the OptimismMessenger before the cross-bridge transaction
    const balanceETHBefore = await baseSepoliaProvider.getBalance(EOAbaseSepolia.address);

    // Build the final payload to be passed from the imaginary Timelock
    const messengerPayload = await optimismMessenger.interface.encodeFunctionData("processMessageFromSource", [data]);
    const minGasLimit = "2000000";
    const timelockPayload = await CDMProxy.interface.encodeFunctionData("sendMessage", [optimismMessengerAddress,
        messengerPayload, minGasLimit]);

    // Send the message to baseSepolia receiver
    if (!sendFundsFromL1) {
        // Funds are not sent from the L1 side, so if the value in payload is non-zero - make sure the L2 contract is fed
        const gasLimit = "3000000";
        tx = await mockTimelock.connect(EOAsepolia).execute(timelockPayload, { gasLimit });
        console.log("Timelock data execution hash", tx.hash);
        await tx.wait();
    } else {
        // If one wants to sent ETH along with the tx, they need to provide much more start up gas limit
        // along with the transferred value, as there are more value specific calculations required pre-transfer
        const gasLimit = "5000000";
        tx = await mockTimelock.connect(EOAsepolia).execute(timelockPayload, { value: amountToSend, gasLimit });
        console.log("Timelock data execution hash", tx.hash);
        await tx.wait();
    }

    // Wait for the event of a processed data on baseSepolia
    // catch NewFxMessage event from mockChildERC20 and MessageReceived event from optimismMessenger
    // Compare the data sent and the data from the NewFxMessage event that must match
    // MessageReceived(uint256 indexed stateId, address indexed sender, bytes message)
    let waitForEvent = true;
    while (waitForEvent) {
        // Check for the last 100 blocks in order to catch the event
        const events = await optimismMessenger.queryFilter("MessageReceived", -200);
        events.forEach((item) => {
            const msg = item["args"]["data"];
            if (msg == data) {
                console.log("Event MessageReceived. Message in baseSepolia:", msg);
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
    const balanceERC20After = Number(await mockChildERC20.balanceOf(EOAbaseSepolia.address));
    const balanceERC20Diff = balanceERC20After - balanceERC20Before;
    if (balanceERC20Diff == amountToMint) {
        console.log("Successfully minted MockChildERC20");
    }

    // Balance of xETH of the OptimismMessenger after the cross-bridge transaction
    const balanceETHAfter = await baseSepoliaProvider.getBalance(EOAbaseSepolia.address);
    const balanceETHDiff = balanceETHAfter - balanceETHBefore;
    if (balanceETHDiff == amountToSend) {
        console.log("Successfully sent xETH");
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
