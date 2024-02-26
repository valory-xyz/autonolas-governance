/*global process*/

const { ethers } = require("ethers");

const sendFundsFromL1 = false;

async function main() {
    const ALCHEMY_API_KEY_GOERLI = process.env.ALCHEMY_API_KEY_GOERLI;
    const goerliURL = "https://eth-goerli.g.alchemy.com/v2/" + ALCHEMY_API_KEY_GOERLI;
    const goerliProvider = new ethers.providers.JsonRpcProvider(goerliURL);
    await goerliProvider.getBlockNumber().then((result) => {
        console.log("Current block number goerli: " + result);
    });

    const celoAlfajoresURL = "https://alfajores-forno.celo-testnet.org";
    const celoAlfajoresProvider = new ethers.providers.JsonRpcProvider(celoAlfajoresURL);
    await celoAlfajoresProvider.getBlockNumber().then((result) => {
        console.log("Current block number celoAlfajores: " + result);
    });

    const fs = require("fs");
    // WormholeRelayer address on goerli
    const wormholeRelayerAddress = "0x28D8F1Be96f97C1387e94A53e00eCcFb4E75175a";
    const wormholeRelayerJSON = "abis/test/WormholeRelayer.json";
    let contractFromJSON = fs.readFileSync(wormholeRelayerJSON, "utf8");
    const wormholeRelayerABI = JSON.parse(contractFromJSON);
    const wormholeRelayer = new ethers.Contract(wormholeRelayerAddress, wormholeRelayerABI, goerliProvider);

    // Test deployed WormholeMessenger address on celoAlfajores
    const wormholeMessengerAddress = "0xeDd71796B90eaCc56B074C39BAC90ED2Ca6D93Ee"; // payable process on L2
    const wormholeMessengerJSON = "artifacts/contracts/bridges/WormholeMessenger.sol/WormholeMessenger.json";
    contractFromJSON = fs.readFileSync(wormholeMessengerJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const wormholeMessengerABI = parsedFile["abi"];
    const wormholeMessenger = new ethers.Contract(wormholeMessengerAddress, wormholeMessengerABI, celoAlfajoresProvider);

    // Mock Timelock contract address on goerli (has WormholeRelayer address in it already)
    const mockTimelockAddress = "0xE5Da5F4d8644A271226161a859c1177C5214c54e"; // payable
    const mockTimelockJSON = "artifacts/contracts/bridges/test/MockTimelock.sol/MockTimelock.json";
    contractFromJSON = fs.readFileSync(mockTimelockJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const mockTimelockABI = parsedFile["abi"];
    const mockTimelock = new ethers.Contract(mockTimelockAddress, mockTimelockABI, goerliProvider);

    // ChildMockERC20 address on celoAlfajores
    const mockChildERC20Address = "0x17806E2a12d5E0F48C9803cd397DB3F044DA3b77";
    const mockChildERC20JSON = "artifacts/contracts/bridges/test/ChildMockERC20.sol/ChildMockERC20.json";
    contractFromJSON = fs.readFileSync(mockChildERC20JSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const mockChildERC20ABI = parsedFile["abi"];
    const mockChildERC20 = new ethers.Contract(mockChildERC20Address, mockChildERC20ABI, celoAlfajoresProvider);

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAgoerli = new ethers.Wallet(account, goerliProvider);
    const EOAceloAlfajores = new ethers.Wallet(account, celoAlfajoresProvider);
    console.log("EOA address",EOAgoerli.address);
    if (EOAceloAlfajores.address == EOAgoerli.address) {
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
        tx = await EOAceloAlfajores.sendTransaction({to: wormholeMessenger.address, value: amountToSend});
        console.log("Send CELO hash", tx.hash);
        await tx.wait();
    }

    // Pack the first part of  with the zero payload
    let target = EOAceloAlfajores.address;
    let value = amountToSend;
    const payloadLength = 0;
    let data = ethers.utils.solidityPack(
        ["address", "uint96", "uint32"],
        [target, value, payloadLength]
    );

    const targetChain = 14; // celo
    const minGasLimit = "2000000";
    const transferCost = await wormholeRelayer["quoteEVMDeliveryPrice(uint16,uint256,uint256)"](targetChain, 0, minGasLimit);

    // Mock Token contract across the bridge must mint 100 OLAS for the deployer
    const rawPayload = mockChildERC20.interface.encodeFunctionData("mint", [EOAceloAlfajores.address, amountToMint]);
    // Pack the second part of data
    target = mockChildERC20Address;
    value = 0;
    const payload = ethers.utils.arrayify(rawPayload);
    data += ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    ).slice(2);

    // Balance of mock tokens before the cross-bridge transaction
    const balanceERC20Before = Number(await mockChildERC20.balanceOf(EOAceloAlfajores.address));
    // Balance of CELO of the WormholeMessenger before the cross-bridge transaction
    const balanceETHBefore = await celoAlfajoresProvider.getBalance(EOAceloAlfajores.address);

    // Build the final payload to be passed from the imaginary Timelock
    const sendPayloadSelector = "0x8fecdd02";
    const timelockPayload = await wormholeRelayer.interface.encodeFunctionData(sendPayloadSelector, [targetChain,
        wormholeMessengerAddress, data, 0, minGasLimit]);

    // Send the message to celoAlfajores receiver
    tx = await mockTimelock.connect(EOAgoerli).execute(timelockPayload, { value: transferCost.nativePriceQuote });
    console.log("Timelock data execution hash", tx.hash);
    await tx.wait();

    // Wait for the event of a processed data on celoAlfajores
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
                console.log("Event MessageReceived. Message in celoAlfajores:", msg);
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
    const balanceERC20After = Number(await mockChildERC20.balanceOf(EOAceloAlfajores.address));
    const balanceERC20Diff = balanceERC20After - balanceERC20Before;
    if (balanceERC20Diff == amountToMint) {
        console.log("Successfully minted MockChildERC20");
    }

    // Balance of CELO of the WormholeMessenger after the cross-bridge transaction
    const balanceETHAfter = await celoAlfajoresProvider.getBalance(EOAceloAlfajores.address);
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
