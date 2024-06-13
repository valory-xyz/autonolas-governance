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

    // Mock Timelock contract address on goerli (has Wormhole Core address in it already)
    const mockTimelockAddress = "0x471B3f60f08C50dd0eCba1bCd113B66FCC02b63d";
    const mockTimelockJSON = "artifacts/contracts/bridges/test/MockTimelock.sol/MockTimelock.json";
    contractFromJSON = fs.readFileSync(mockTimelockJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const mockTimelockABI = parsedFile["abi"];
    const mockTimelock = new ethers.Contract(mockTimelockAddress, mockTimelockABI, sepoliaProvider);

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAsepolia = new ethers.Wallet(account, sepoliaProvider);
    console.log(EOAsepolia.address);

    // Wrap the data to send over the bridge
    // Transfer selector: 2 => u8 or 1 byte
    const transferSelector = "02";
    // Source address (ATA) SOL (DygsTMRqfNbRMTmczXyTMaKuQtkPNPQVsGe2zMhKP4rG) in hex16: 32 bytes
    const sourceAddressSol = "c0d1d976aaf0bc1676d1d7391c4aba6feeb3db165eb9718503486aba26c100a5";
    // Source address (ATA) OLAS (HJzBPrhZyMk3rbrnWxpRXXfPiymNXrWkP77rfo6MBh9e) in hex16: 32 bytes
    const sourceAddressOlas = "f256846e9e70dd9acd35d810de70d21ba4242c60c3d74ec146a5c949c0199a05";
    // Destination address  (9fit3w7t6FHATDaZWotpWqN7NpqgL3Lm1hqUop4hAy8h) in hex16: 32 bytes
    const destinationAddress = "80c8eb941bc025de8750e8a753630e2b6e7b96d5132f5f3f5a9228caf6521c26";

    // Assemble the data
    const data = "0x" + transferSelector + sourceAddressSol + sourceAddressOlas + destinationAddress;

    const wormholeFinality = 0; // 0 = confirmed, 1 = finalized
    const payload = wormhole.interface.encodeFunctionData("publishMessage", [0, data, wormholeFinality]);
    console.log(payload);
    const tx = await mockTimelock.connect(EOAsepolia).execute(payload);
    console.log("Timelock data execution hash", tx.hash);
    await tx.wait();

    // tx: 0x70a103c57b85c65cb1364ee37b7f502f57d41fcb567e607da18033537db2c7db
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
