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
    // Transfer selector: 1 => u8 or 1 byte
    const transferSelector = "01";
    // Source address (ATA) SOL (DygsTMRqfNbRMTmczXyTMaKuQtkPNPQVsGe2zMhKP4rG) in hex16: 32 bytes
    const sourceAddressSol = "c0d1d976aaf0bc1676d1d7391c4aba6feeb3db165eb9718503486aba26c100a5";
    // Source address (ATA) OLAS (HJzBPrhZyMk3rbrnWxpRXXfPiymNXrWkP77rfo6MBh9e) in hex16: 32 bytes
    const sourceAddressOlas = "f256846e9e70dd9acd35d810de70d21ba4242c60c3d74ec146a5c949c0199a05";
    // Destination address (ATA) SOL  (JACBSWcdwYRFeP8Ab5v2d4Z2AVH4v4Fx2JTomqKARd6m) in hex16: 32 bytes
    const destinationAddressSol = "fef18bd9d863fe9221ccecc49230be8cd53c5c543654d715136137c99c9570ee";
    // Destination address (ATA) OLAS  (7e8LRrfeeSGfS2SSVGJMZQLQKzYhkBp8VKtt34uJMR4t) in hex16: 32 bytes
    const destinationAddressOlas = "62a8e7b9a914c06fd22809b7e2d1baab4fa41a5429b10bebbe51b4dc32310ab1";

    // Assemble the data
    const data = "0x" + transferSelector + sourceAddressSol + sourceAddressOlas + destinationAddressSol + destinationAddressOlas;

    const wormholeFinality = 0; // 0 = confirmed, 1 = finalized
    const payload = wormhole.interface.encodeFunctionData("publishMessage", [0, data, wormholeFinality]);
    console.log(payload);
    const tx = await mockTimelock.connect(EOAsepolia).execute(payload);
    console.log("Timelock data execution hash", tx.hash);
    await tx.wait();

    // tx: 0x4818d0a9a89173797ff716ee34cc9c5a88f36a62acdfe4e484ebe6c37835a139
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
