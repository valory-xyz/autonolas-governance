/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);

    const treasuryAddress = parsedData.treasuryAddress;
    const depositoryAddress = "0x5FDc466f4A7547c876eF40CD30fFA2A89F1EcDE7";
    const serviceRegistryTokenUtilityAddress = "0x6d9b08701Af43D68D991c074A27E4d90Af7f2276";
    const serviceRegistryL2PolygonAddress = "0xf805DfF246CC208CD2F08ffaD242b7C32bc93623";
    const serviceRegistryTokenUtilityPolygonAddress="0x131b5551c81e9B3E89E9ACE30A5B3D45144E3e42";
    const serviceRegistryL2GnosisAddress = "0x31D3202d8744B16A120117A053459DDFAE93c855";
    const serviceRegistryTokenUtilityGnosisAddress = "0xc2c7E40674f1C7Bb99eFe5680Efd79842502bED4";
    const guardCMAddress = parsedData.guardCMAddress;
    const AMBContractProxyForeignAddress = "0x87A19d769D875964E9Cd41dDBfc397B2543764E6";
    const homeMediatorAddress = "0x670Ac235EE13C0B2a5065282bBB0c61cfB354592";
    const fxRootAddress = "0x3d1d3E34f7fB6D26245E6640E1c50710eFFf15bA"; 
    const fxGovernorTunnelAddress = "0x17806E2a12d5E0F48C9803cd397DB3F044DA3b77";



    // Obtaining proposal values
    console.log("Guard CM setup");
    const guardCM = await ethers.getContractAt("GuardCM", guardCMAddress);
    const targets = [guardCMAddress, guardCMAddress];
    const values = new Array(2).fill(0);
    const callDatas = [
        guardCM.interface.encodeFunctionData("setBridgeMediatorChainIds", [[AMBContractProxyForeignAddress, fxRootAddress],
            [homeMediatorAddress, fxGovernorTunnelAddress], ["10200", "80001"]]),
        guardCM.interface.encodeFunctionData("setTargetSelectorChainIds", [[treasuryAddress, treasuryAddress, depositoryAddress,
            serviceRegistryTokenUtilityAddress, serviceRegistryL2PolygonAddress, serviceRegistryTokenUtilityPolygonAddress, serviceRegistryL2GnosisAddress,
            serviceRegistryTokenUtilityGnosisAddress],
        ["0x8456cb59", "0x8f202bf9", "0x58d3ec6a", "0xece53132", "0x9890220b","0xece53132", "0x9890220b", "0xece53132"],
        [5, 5, 5, 5, 80001, 80001, 10200, 10200],
        [true, true, true, true, true, true, true, true]])
    ];
    const description = "Guard CM setup";

    // Proposal details
    console.log("targets:", targets);
    console.log("values:", values);
    console.log("call datas:", callDatas);
    console.log("description:", description);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
