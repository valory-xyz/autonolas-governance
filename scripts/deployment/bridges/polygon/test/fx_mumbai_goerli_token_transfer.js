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
    const fxRootJSON = "artifacts/lib/fx-portal/contracts/FxRoot.sol/FxRoot.json";
    let contractFromJSON = fs.readFileSync(fxRootJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const fxRootABI = parsedFile["abi"];
    const fxRoot = new ethers.Contract(fxRootAddress, fxRootABI, goerliProvider);

    // FxChild address on mumbai
    const fxChildAddress = "0xCf73231F28B7331BBe3124B907840A94851f9f11";
    const fxChildJSON = "artifacts/lib/fx-portal/contracts/FxChild.sol/FxChild.json";
    contractFromJSON = fs.readFileSync(fxChildJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const fxChildABI = parsedFile["abi"];
    const fxChild = new ethers.Contract(fxChildAddress, fxChildABI, mumbaiProvider);

    // ChildMockERC20 address on mumbai
    const mockChildERC20Address = "0xeB49bE5DF00F74bd240DE4535DDe6Bc89CEfb994";
    const mockChildERC20JSON = "artifacts/contracts/bridges/test/ChildMockERC20.sol/ChildMockERC20.json";
    contractFromJSON = fs.readFileSync(mockChildERC20JSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const mockChildERC20ABI = parsedFile["abi"];
    const mockChildERC20 = new ethers.Contract(mockChildERC20Address, mockChildERC20ABI, mumbaiProvider);

    // BridgedERC20 address on goerli
    const bridgedERC20Address = "0x88e4ad16Bd4953Bbe74589942b368969037a7d81";
    const bridgedERC20JSON = "artifacts/contracts/bridges/BridgedERC20.sol/BridgedERC20.json";
    contractFromJSON = fs.readFileSync(bridgedERC20JSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const bridgedERC20ABI = parsedFile["abi"];
    const bridgedERC20 = new ethers.Contract(bridgedERC20Address, bridgedERC20ABI, goerliProvider);

    // Test deployed FxERC20ChildTunnel address on mumbai
    const fxERC20ChildTunnelAddress = "0x1d333b46dB6e8FFd271b6C2D2B254868BD9A2dbd";
    const fxERC20ChildTunnelJSON = "artifacts/contracts/bridges/FxERC20ChildTunnel.sol/FxERC20ChildTunnel.json";
    contractFromJSON = fs.readFileSync(fxERC20ChildTunnelJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const fxERC20ChildTunnelABI = parsedFile["abi"];
    const fxERC20ChildTunnel = new ethers.Contract(fxERC20ChildTunnelAddress, fxERC20ChildTunnelABI, mumbaiProvider);
    const verifyFxChildAddress = await fxERC20ChildTunnel.fxChild();
    if (fxChildAddress == verifyFxChildAddress) {
        console.log("Successfully connected to the test fxERC20ChildTunnel contract");
    }

    // Test deployed FxERC20RootTunnel address on goerli
    const fxERC20RootTunnelAddress = "0x1479f01AbdC9b33e6a40F4b03dD38521e3feF98e";
    const fxERC20RootTunnelJSON = "artifacts/contracts/bridges/FxERC20RootTunnel.sol/FxERC20RootTunnel.json";
    contractFromJSON = fs.readFileSync(fxERC20RootTunnelJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const fxERC20RootTunnelABI = parsedFile["abi"];
    const fxERC20RootTunnel = new ethers.Contract(fxERC20RootTunnelAddress, fxERC20RootTunnelABI, goerliProvider);
    const verifyFxRootAddress = await fxERC20RootTunnel.fxRoot();
    if (fxRootAddress == verifyFxRootAddress) {
        console.log("Successfully connected to the test fxERC20RootTunnel contract");
    }

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAgoerli = new ethers.Wallet(account, goerliProvider);
    const EOAmumbai = new ethers.Wallet(account, mumbaiProvider);
    console.log("EOA", EOAgoerli.address);
    if (EOAmumbai.address == EOAgoerli.address) {
        console.log("Correct wallet setup");
    }

    //    const balance = await mockChildERC20.balanceOf(fxERC20ChildTunnel.address);
    //    console.log(balance);
    //    return;

    // Deposit tokens for goerli bridged ERC20 ones
    await mockChildERC20.connect(EOAmumbai).approve(fxERC20ChildTunnel.address, 10);
    const tx = await fxERC20ChildTunnel.connect(EOAmumbai).deposit(10);
    console.log(tx.hash);
    await tx.wait();

    // Wait for the event of a processed data on mumbai and then goerli
    let waitForEvent = true;
    while (waitForEvent) {
        // Check for the last 100 blocks in order to catch the event
        const events = await fxERC20RootTunnel.queryFilter("FxDepositERC20", -100);
        events.forEach((item) => {
            console.log("Catch event FxDepositERC20:", item);
            waitForEvent = false;
        });
        // Continue waiting for the event if none was received
        if (waitForEvent) {
            console.log("Waiting for the receive event, next update in 300 seconds ...");
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
