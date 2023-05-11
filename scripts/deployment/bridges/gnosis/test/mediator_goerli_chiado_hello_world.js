/*global process*/

const { ethers } = require("ethers");

async function main() {
    const ALCHEMY_API_KEY_GOERLI = process.env.ALCHEMY_API_KEY_GOERLI;
    const goerliURL = "https://eth-goerli.g.alchemy.com/v2/" + ALCHEMY_API_KEY_GOERLI;
    const goerliProvider = new ethers.providers.JsonRpcProvider(goerliURL);
    await goerliProvider.getBlockNumber().then((result) => {
        console.log("Current block number goerli: " + result);
    });

    const chiadoURL = "https://rpc.chiadochain.net";
    const chiadoProvider = new ethers.providers.JsonRpcProvider(chiadoURL);
    await chiadoProvider.getBlockNumber().then((result) => {
        console.log("Current block number chiado: " + result);
    });

    const fs = require("fs");
    // AMBProxy address on goerli
    const AMBProxyAddress = "0x87A19d769D875964E9Cd41dDBfc397B2543764E6";
    const AMBProxyJSON = "abis/test/EternalStorageProxy.json";
    let contractFromJSON = fs.readFileSync(AMBProxyJSON, "utf8");
    const AMBProxyABI = JSON.parse(contractFromJSON);
    const AMBProxy = new ethers.Contract(AMBProxyAddress, AMBProxyABI, goerliProvider);

    // Test deployed HomeMediator address on chiado
    const homeMediatorAddress = "0x17806E2a12d5E0F48C9803cd397DB3F044DA3b77";
    const homeMediatorJSON = "artifacts/contracts/bridges/test/HomeMediatorTest.sol/HomeMediatorTest.json";
    contractFromJSON = fs.readFileSync(homeMediatorJSON, "utf8");
    const parsedFile = JSON.parse(contractFromJSON);
    const homeMediatorABI = parsedFile["abi"];
    const homeMediator = new ethers.Contract(homeMediatorAddress, homeMediatorABI, chiadoProvider);

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAgoerli = new ethers.Wallet(account, goerliProvider);
    const EOAchiado = new ethers.Wallet(account, chiadoProvider);
    console.log("EOA",EOAgoerli.address);
    if (EOAchiado.address == EOAgoerli.address) {
        console.log("Correct wallet setup");
    }

    // Wrap the data to send over the bridge
    // hello world == 68656c6c6f20776f726c64
    const data = "0x68656c6c6f20776f726c64";
    const timelockPayload = await homeMediator.interface.encodeFunctionData("processMessageFromForeign", [data]);
    // Send the message to chiado receiver
    const requestGasLimit = "2000000";
    await AMBProxy.connect(EOAgoerli).requireToPassMessage(homeMediatorAddress, timelockPayload, requestGasLimit);

    // Wait for the event of a processed data on chiado
    // catch MessageReceived event from the HomeMediator contract
    // Compare the data sent and the data from the HomeMediator event that must match
    // MessageReceived(address indexed foreignMessageSender, bytes data)
    let waitForEvent = true;
    while (waitForEvent) {
        // Check for the last 100 blocks in order to catch the event
        const events = await homeMediator.queryFilter("MessageReceived", -200);
        events.forEach((item) => {
            const msg = item["args"]["data"];
            if (msg == data) {
                console.log("Event MessageReceived. Message on chiado:", msg);
                waitForEvent = false;
            } else {
                console.log("Wrong Event MessageReceived. Message on chiado:", msg);
            }
        });
        // Continue waiting for the event if none was received
        if (waitForEvent) {
            console.log("Waiting for the receive event, next update in 5 minutes ...");
            // Sleep for a minute
            await new Promise(r => setTimeout(r, 300000));
        }
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
