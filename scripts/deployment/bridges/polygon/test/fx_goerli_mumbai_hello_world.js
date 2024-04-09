/*global process*/

const { ethers } = require("ethers");

async function main() {
    const ALCHEMY_API_KEY_GOERLI = process.env.ALCHEMY_API_KEY_GOERLI;
    const goerliURL = "https://eth-goerli.g.alchemy.com/v2/" + ALCHEMY_API_KEY_GOERLI;
    const goerliProvider = new ethers.providers.JsonRpcProvider(goerliURL);
    await goerliProvider.getBlockNumber().then((result) => {
        console.log("Current block number goerli: " + result);
    });

    const ALCHEMY_API_KEY_MUMBAI = process.env.ALCHEMY_API_KEY_MUMBAI;
    const mumbaiURL = "https://polygon-mumbai.g.alchemy.com/v2/" + ALCHEMY_API_KEY_MUMBAI;
    const mumbaiProvider = new ethers.providers.JsonRpcProvider(mumbaiURL);
    await mumbaiProvider.getBlockNumber().then((result) => {
        console.log("Current block number mumbai: " + result);
    });

    const fs = require("fs");
    // FxRoot address on goerli
    const fxRootAddress = "0x3d1d3E34f7fB6D26245E6640E1c50710eFFf15bA";
    const fxRootJSON = "artifacts/fx-portal/contracts/FxRoot.sol/FxRoot.json";
    let contractFromJSON = fs.readFileSync(fxRootJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const fxRootABI = parsedFile["abi"];
    const fxRoot = new ethers.Contract(fxRootAddress, fxRootABI, goerliProvider);

    // Test deployed FxChildTunnel address on mumbai
    const fxChildTunnelAddress = "0x31D3202d8744B16A120117A053459DDFAE93c855";
    const fxChildTunnelJSON = "artifacts/contracts/bridges/test/FxChildTunnel.sol/FxChildTunnel.json";
    contractFromJSON = fs.readFileSync(fxChildTunnelJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const fxChildTunnelABI = parsedFile["abi"];
    const fxChildTunnel = new ethers.Contract(fxChildTunnelAddress, fxChildTunnelABI, mumbaiProvider);
    const verifyFxChildAddress = await fxChildTunnel.fxChild();

    const fxChildAddress = "0xCf73231F28B7331BBe3124B907840A94851f9f11";
    if (fxChildAddress == verifyFxChildAddress) {
        console.log("Successfully connected to the test fxChildTunnel contract");
    }

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAgoerli = new ethers.Wallet(account, goerliProvider);
    const EOAmumbai = new ethers.Wallet(account, mumbaiProvider);
    console.log("EOA",EOAgoerli.address);
    if(EOAmumbai.address == EOAgoerli.address) {
        console.log("Correct wallet setup");
    }

    // Wrap the data to send over the bridge
    // hello world == 68656c6c6f20776f726c64
    const data = "0x68656c6c6f20776f726c64";
    // Send the message to mumbai receiver
    await fxRoot.connect(EOAgoerli).sendMessageToChild(fxChildTunnelAddress, data);

    // Wait for the event of a processed data on mumbai
    // catch NewFxMessage event from fxChild and MessageReceived event from fxChildTunnel
    // Compare the data sent and the data from the NewFxMessage event that must match
    // MessageReceived(uint256 indexed stateId, address indexed sender, bytes message)
    let waitForEvent = true;
    while (waitForEvent) {
        // Check for the last 100 blocks in order to catch the event
        const events = await fxChildTunnel.queryFilter("MessageReceived", -100);
        events.forEach((item) => {
            const msg = item["args"]["message"];
            if(msg == data) {
                console.log("Catch event MessageReceived. OK. Message in mumbai equal:", msg);
                waitForEvent = false;
            } else {
                console.log("Catch event MessageReceived. Fail. Message in mumbai not equal:", msg);
            }
        });
        // Continue waiting for the event if none was received
        if (waitForEvent) {
            console.log("Waiting for the receive event, next update in 60 seconds ...");
            // Sleep for a minute
            await new Promise(r => setTimeout(r, 60000));
        }
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
