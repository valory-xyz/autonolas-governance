/*global process*/

const { ethers } = require("ethers");

async function main() {
    const ALCHEMY_API_KEY_MATIC = process.env.ALCHEMY_API_KEY_MATIC;
    const polygonURL = "https://polygon-mainnet.g.alchemy.com/v2/" + ALCHEMY_API_KEY_MATIC;
    const polygonProvider = new ethers.providers.JsonRpcProvider(polygonURL);
    await polygonProvider.getBlockNumber().then((result) => {
        console.log("Current block number polygon: " + result);
    });

    const fs = require("fs");
    // Wormhole Core address on polygon
    const wormholeAddress = "0x7A4B5a56256163F07b2C80A7cA55aBE66c4ec4d7";
    const wormholeJSON = "abis/test/WormholeCore.json";
    let contractFromJSON = fs.readFileSync(wormholeJSON, "utf8");
    const wormholeABI = JSON.parse(contractFromJSON);
    const wormhole = new ethers.Contract(wormholeAddress, wormholeABI, polygonProvider);

    // Mock Timelock contract address on sepolia (has Wormhole Core address in it already)
    const mockTimelockAddress = "0x4cEB52802ef86edF8796632546d89e55c87a0901";
    const mockTimelockJSON = "artifacts/contracts/bridges/test/MockTimelock.sol/MockTimelock.json";
    contractFromJSON = fs.readFileSync(mockTimelockJSON, "utf8");
    const parsedFile = JSON.parse(contractFromJSON);
    const mockTimelockABI = parsedFile["abi"];
    const mockTimelock = new ethers.Contract(mockTimelockAddress, mockTimelockABI, polygonProvider);

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOApolygon = new ethers.Wallet(account, polygonProvider);
    console.log(EOApolygon.address);

    // Wrap the data to send over the bridge
    // hello world == 68656c6c6f20776f726c64
    const data = "0x68656c6c6f20776f726c64";

    const wormholeFinality = 0; // 0 = confirmed, 1 = finalized
    const payload = wormhole.interface.encodeFunctionData("publishMessage", [0, data, wormholeFinality]);
    console.log(payload);
    const gasPrice = ethers.utils.parseUnits("40", "gwei");
    const tx = await mockTimelock.connect(EOApolygon).execute(payload, { gasPrice });
    console.log("Timelock data execution hash", tx.hash);
    await tx.wait();

    // https://wormholescan.io/#/tx/0x7b0145014a4e8f0d8621fbc0e366460dda3ba307732eff539f7c1e8e6589718a?view=advanced
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
