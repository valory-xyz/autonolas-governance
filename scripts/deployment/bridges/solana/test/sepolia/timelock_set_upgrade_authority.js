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
    // Upgrade authority selector: 3 => u8 or 1 byte
    const upgradeAuthoritySelector = "03";
    // Program account address (1okwt4nGbpr82kkr6t1767sAenfeZBxUyzJAAaumZRG) in hex16: 32 bytes
    const programAddress = "0034de7cd749206ba916b55439381fb6b519e11757ee5ec12422151589bd337f";
    // Upgrade authority address (9fit3w7t6FHATDaZWotpWqN7NpqgL3Lm1hqUop4hAy8h) in hex16: 32 bytes
    const authorityAddress = "80c8eb941bc025de8750e8a753630e2b6e7b96d5132f5f3f5a9228caf6521c26";

    // Assemble the data
    const data = "0x" + upgradeAuthoritySelector + programAddress + authorityAddress;

    const wormholeFinality = 0; // 0 = confirmed, 1 = finalized
    const payload = wormhole.interface.encodeFunctionData("publishMessage", [0, data, wormholeFinality]);
    console.log(payload);
    const tx = await mockTimelock.connect(EOAsepolia).execute(payload);
    console.log("Timelock data execution hash", tx.hash);
    await tx.wait();

    // tx: 0x577390c8d516cb74bec3d87c42fb50c454f87864e2dbe39839a1753407ca1e96
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
