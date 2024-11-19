/*global process*/

const { ethers } = require("ethers");

async function main() {
    const ALCHEMY_API_KEY_SEPOLIA = process.env.ALCHEMY_API_KEY_SEPOLIA;
    const sepoliaURL = "https://eth-sepolia.g.alchemy.com/v2/" + ALCHEMY_API_KEY_SEPOLIA;
    const sepoliaProvider = new ethers.providers.JsonRpcProvider(sepoliaURL);
    await sepoliaProvider.getBlockNumber().then((result) => {
        console.log("Current block number sepolia: " + result);
    });

    const fs = require("fs");
    // Wormhole Core address on sepolia
    const wormholeAddress = "0x4a8bc80Ed5a4067f1CCf107057b8270E0cC11A78";
    const wormholeJSON = "abis/test/WormholeCore.json";
    let contractFromJSON = fs.readFileSync(wormholeJSON, "utf8");
    const wormholeABI = JSON.parse(contractFromJSON);
    const wormhole = new ethers.Contract(wormholeAddress, wormholeABI, sepoliaProvider);

    // Mock Timelock contract address on sepolia (has Wormhole Core address in it already)
    const mockTimelockAddress = "0x471B3f60f08C50dd0eCba1bCd113B66FCC02b63d";
    const mockTimelockJSON = "artifacts/contracts/bridges/test/MockTimelock.sol/MockTimelock.json";
    contractFromJSON = fs.readFileSync(mockTimelockJSON, "utf8");
    const parsedFile = JSON.parse(contractFromJSON);
    const mockTimelockABI = parsedFile["abi"];
    const mockTimelock = new ethers.Contract(mockTimelockAddress, mockTimelockABI, sepoliaProvider);

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAsepolia = new ethers.Wallet(account, sepoliaProvider);
    console.log(EOAsepolia.address);

    // Wrap the data to send over the bridge
    // Data: registries contract functions: paused(), version()
    const data = "0x5b7b22636f6e74726163745f6964223a22636f6e74726163745f3030302e7375625f6f6c61732e6f6c61735f3030302e746573746e6574222c226465706f736974223a2230222c22676173223a352c226d6574686f645f6e616d65223a2269735f706175736564222c2261726773223a5b5d7d2c7b22636f6e74726163745f6964223a22636f6e74726163745f3030302e7375625f6f6c61732e6f6c61735f3030302e746573746e6574222c226465706f736974223a2230222c22676173223a352c226d6574686f645f6e616d65223a2276657273696f6e222c2261726773223a5b5d7d5d";

    const wormholeFinality = 0; // 0 = confirmed, 1 = finalized
    const payload = wormhole.interface.encodeFunctionData("publishMessage", [0, data, wormholeFinality]);
    console.log(payload);
    const tx = await mockTimelock.connect(EOAsepolia).execute(payload);
    console.log("Timelock data execution hash", tx.hash);
    await tx.wait();

    // 2 view functions: https://wormholescan.io/#/tx/0xfa83667d2226033cfe562ac216875de625fe55b2744fd801a63a8b52645edc64?network=Testnet&view=overview
    // 2 view functions and 1 payable: https://wormholescan.io/#/tx/0xebc96800331e6c6b309c8612dbddb14bbf078eb3fa80afdfeaf66ad43969399f?network=Testnet&view=overview
    // 2 view functions and 1 payable with gas: https://wormholescan.io/#/tx/0x45c4585ba16c3c4e147e9bbc690954d7455dc6939b220ac0ea5e9a241facbd28?network=Testnet&view=overview
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
