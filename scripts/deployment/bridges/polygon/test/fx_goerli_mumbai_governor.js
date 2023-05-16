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

    // Mock Timelock contract address on goerli (has FxRoot address in it already)
    const mockTimelockAddress = "0x95dA0F8C3eC5D40209f0EF1ED5E61deD28307d8d";
    const mockTimelockJSON = "artifacts/contracts/bridges/test/MockTimelock.sol/MockTimelock.json";
    contractFromJSON = fs.readFileSync(mockTimelockJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const mockTimelockABI = parsedFile["abi"];
    const mockTimelock = new ethers.Contract(mockTimelockAddress, mockTimelockABI, goerliProvider);

    // ChildMockERC20 address on mumbai
    const mockChildERC20Address = "0xeB49bE5DF00F74bd240DE4535DDe6Bc89CEfb994";
    const mockChildERC20JSON = "artifacts/contracts/bridges/test/ChildMockERC20.sol/ChildMockERC20.json";
    contractFromJSON = fs.readFileSync(mockChildERC20JSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const mockChildERC20ABI = parsedFile["abi"];
    const mockChildERC20 = new ethers.Contract(mockChildERC20Address, mockChildERC20ABI, mumbaiProvider);

    // Test deployed FxGovernorTunnel address on mumbai
    const fxGovernorTunnelAddress = "0x29086141ecdc310058fc23273F8ef7881d20C2f7";
    const fxGovernorTunnelJSON = "artifacts/contracts/bridges/FxGovernorTunnel.sol/FxGovernorTunnel.json";
    contractFromJSON = fs.readFileSync(fxGovernorTunnelJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const fxGovernorTunnelABI = parsedFile["abi"];
    const fxGovernorTunnel = new ethers.Contract(fxGovernorTunnelAddress, fxGovernorTunnelABI, mumbaiProvider);

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAgoerli = new ethers.Wallet(account, goerliProvider);
    const EOAmumbai = new ethers.Wallet(account, mumbaiProvider);
    console.log("EOA",EOAgoerli.address);
    if(EOAmumbai.address == EOAgoerli.address) {
        console.log("Correct wallet setup");
    }

    // Amount of MATIC to send
    const amountToSend = ethers.utils.parseEther("0.1");
    // Amount of ERC20 token to mint
    const amountToMint = 100;

    // Send funds to the FxGovernorTunnel contract
    let tx = await EOAmumbai.sendTransaction({to: fxGovernorTunnel.address, value: amountToSend});
    console.log("Send MATIC hash", tx.hash);
    await tx.wait();

    // Pack the first part of data with the zero payload
    let target = EOAmumbai.address;
    let value = amountToSend;
    const payloadLength = 0;
    let data = ethers.utils.solidityPack(
        ["address", "uint96", "uint32"],
        [target, value, payloadLength]
    );

    // Mock Token contract across the bridge must mint 100 OLAS for the deployer
    const rawPayload = mockChildERC20.interface.encodeFunctionData("mint", [EOAmumbai.address, amountToMint]);
    // Pack the second part of data
    target = mockChildERC20Address;
    value = 0;
    const payload = ethers.utils.arrayify(rawPayload);
    data += ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    ).slice(2);

    // Balance of mock tokens before the cross-bridge transaction
    const balanceERC20Before = Number(await mockChildERC20.balanceOf(EOAmumbai.address));
    // Balance of MATIC of the FxGovernorTunnel before the cross-bridge transaction
    const balanceMATICBefore = await mumbaiProvider.getBalance(EOAmumbai.address);

    // Send the message to mumbai receiver from the timelock
    const timelockPayload = await fxRoot.interface.encodeFunctionData("sendMessageToChild", [fxGovernorTunnelAddress, data]);
    tx = await mockTimelock.connect(EOAgoerli).execute(timelockPayload);
    console.log(tx.hash);
    await tx.wait();

    // Wait for the event of a processed data on mumbai
    // catch NewFxMessage event from mockChildERC20 and MessageReceived event from fxGovernorTunnel
    // Compare the data sent and the data from the NewFxMessage event that must match
    // MessageReceived(uint256 indexed stateId, address indexed sender, bytes message)
    let waitForEvent = true;
    while (waitForEvent) {
        // Check for the last 100 blocks in order to catch the event
        const events = await fxGovernorTunnel.queryFilter("MessageReceived", -200);
        events.forEach((item) => {
            const msg = item["args"]["data"];
            if (msg == data) {
                console.log("Event MessageReceived. OK. Message in mumbai:", msg);
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
    const balanceERC20After = Number(await mockChildERC20.balanceOf(EOAmumbai.address));
    const balanceERC20Diff = balanceERC20After - balanceERC20Before;
    if (balanceERC20Diff == amountToMint) {
        console.log("Successfully minted MockChildERC20");
    }

    // Balance of MATIC of the FxGovernorTunnel after the cross-bridge transaction
    const balanceMATICAfter = await mumbaiProvider.getBalance(EOAmumbai.address);
    const balanceMATICDiff = balanceMATICAfter - balanceMATICBefore;
    if (balanceMATICDiff == amountToSend) {
        console.log("Successfully sent MATIC");
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
