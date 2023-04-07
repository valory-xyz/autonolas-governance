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

    // FxRoot address on mumbai
    const fxChildAddress = "0xCf73231F28B7331BBe3124B907840A94851f9f11";
    const fxChildJSON = "artifacts/fx-portal/contracts/FxChild.sol/FxChild.json";
    contractFromJSON = fs.readFileSync(fxChildJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const fxChildABI = parsedFile["abi"];
    const fxChild = new ethers.Contract(fxChildAddress, fxChildABI, mumbaiProvider);

    // FxChildTunnel address on mumbai
    const fxChildTunnelAddress = "0x31D3202d8744B16A120117A053459DDFAE93c855";
    const fxChildTunnelJSON = "artifacts/contracts/bridges/FxChildTunnel.sol/FxChildTunnel.json";
    contractFromJSON = fs.readFileSync(fxChildTunnelJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const fxChildTunnelABI = parsedFile["abi"];
    const fxChildTunnel = new ethers.Contract(fxChildTunnelAddress, fxChildTunnelABI, mumbaiProvider);
    const verifyFxChildAddress = await fxChildTunnel.fxChild();
    if (fxChildAddress == verifyFxChildAddress) {
        console.log("Successfully connected to the fxChildTunnel contract");
    }

    // Get the EOA
    const EOA = 0;

    // Wrap the data to send over the bridge
    const data = "0x";
    // Send the message to mumbai receiver
    await fxRoot.connect(EOA).sendMessageToChild(fxChildTunnelAddress, data);

    // Wait for the event of a processed data on mumbai
    // catch NewFxMessage event from fxChild and MessageReceived event from fxChildTunnel
    // Compare the data sent and the data from the NewFxMessage event that must match
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
