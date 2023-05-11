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
    const homeMediatorAddress = "0x0a50009D55Ed5700ac8FF713709d5Ad5fa843896";
    const homeMediatorJSON = "artifacts/contracts/bridges/HomeMediator.sol/HomeMediator.json";
    contractFromJSON = fs.readFileSync(homeMediatorJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const homeMediatorABI = parsedFile["abi"];
    const homeMediator = new ethers.Contract(homeMediatorAddress, homeMediatorABI, chiadoProvider);

    // Mock Timelock contract address on goerli (has AMBProxy address in it already)
    const mockTimelockAddress = "0x5b03476a21e9c7cEB8dB1Bd9F24664e480FDcc43";
    const mockTimelockJSON = "artifacts/contracts/bridges/test/MockTimelock.sol/MockTimelock.json";
    contractFromJSON = fs.readFileSync(mockTimelockJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const mockTimelockABI = parsedFile["abi"];
    const mockTimelock = new ethers.Contract(mockTimelockAddress, mockTimelockABI, goerliProvider);

    // ChildMockERC20 address on chiado
    const mockChildERC20Address = "0x77290FF625fc576f465D0256F6a12Ce4480a5b8a";
    const mockChildERC20JSON = "artifacts/contracts/bridges/test/ChildMockERC20.sol/ChildMockERC20.json";
    contractFromJSON = fs.readFileSync(mockChildERC20JSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const mockChildERC20ABI = parsedFile["abi"];
    const mockChildERC20 = new ethers.Contract(mockChildERC20Address, mockChildERC20ABI, chiadoProvider);

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAgoerli = new ethers.Wallet(account, goerliProvider);
    const EOAchiado = new ethers.Wallet(account, chiadoProvider);
    console.log("EOA address",EOAgoerli.address);
    if (EOAchiado.address == EOAgoerli.address) {
        console.log("Correct wallet setup");
    }

    // Amount of xDAI to send
    const amountToSend = ethers.utils.parseEther("0.1");
    // Amount of ERC20 token to mint
    const amountToMint = 100;

    // Send funds to the HomeMediator contract
    let tx = await EOAchiado.sendTransaction({to: homeMediator.address, value: amountToSend});
    console.log("Send xDAI hash", tx.hash);
    await tx.wait();

    // Pack the first part of  with the zero payload
    let target = EOAchiado.address;
    let value = amountToSend;
    const payloadLength = 0;
    let data = ethers.utils.solidityPack(
        ["address", "uint96", "uint32"],
        [target, value, payloadLength]
    );

    // Mock Token contract across the bridge must mint 100 OLAS for the deployer
    const rawPayload = mockChildERC20.interface.encodeFunctionData("mint", [EOAchiado.address, amountToMint]);
    // Pack the second part of data
    target = mockChildERC20Address;
    value = 0;
    const payload = ethers.utils.arrayify(rawPayload);
    data += ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    ).slice(2);

    // Balance of mock tokens before the cross-bridge transaction
    const balanceERC20Before = Number(await mockChildERC20.balanceOf(EOAchiado.address));
    // Balance of xDAI of the HomeMediator before the cross-bridge transaction
    const balanceDAIBefore = await chiadoProvider.getBalance(EOAchiado.address);

    // Build the final payload to be passed from the imaginary Timelock
    const mediatorPayload = await homeMediator.interface.encodeFunctionData("processMessageFromForeign", [data]);
    const requestGasLimit = "2000000";
    const timelockPayload = await AMBProxy.interface.encodeFunctionData("requireToPassMessage", [homeMediatorAddress,
        mediatorPayload, requestGasLimit]);

    // Send the message to chiado receiver
    tx = await mockTimelock.connect(EOAgoerli).execute(timelockPayload);
    console.log("Timelock data execution hash", tx.hash);
    await tx.wait();

    // Wait for the event of a processed data on chiado
    // catch NewFxMessage event from mockChildERC20 and MessageReceived event from homeMediator
    // Compare the data sent and the data from the NewFxMessage event that must match
    // MessageReceived(uint256 indexed stateId, address indexed sender, bytes message)
    let waitForEvent = true;
    while (waitForEvent) {
        // Check for the last 100 blocks in order to catch the event
        const events = await homeMediator.queryFilter("MessageReceived", -200);
        events.forEach((item) => {
            const msg = item["args"]["data"];
            if (msg == data) {
                console.log("Event MessageReceived. Message in chiado:", msg);
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
    const balanceERC20After = Number(await mockChildERC20.balanceOf(EOAchiado.address));
    const balanceERC20Diff = balanceERC20After - balanceERC20Before;
    if (balanceERC20Diff == amountToMint) {
        console.log("Successfully minted MockChildERC20");
    }

    // Balance of xDAI of the HomeMediator after the cross-bridge transaction
    const balanceDAIAfter = await chiadoProvider.getBalance(EOAchiado.address);
    const balanceDAIDiff = balanceDAIAfter - balanceDAIBefore;
    if (balanceDAIDiff == amountToSend) {
        console.log("Successfully sent xDAI");
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
