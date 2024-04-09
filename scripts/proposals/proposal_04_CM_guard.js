/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);

    const treasuryAddress = parsedData.treasuryAddress;
    const depositoryAddress = parsedData.depositoryAddress;
    const serviceRegistryTokenUtilityAddress = "0x3Fb926116D454b95c669B6Bf2E7c3bad8d19affA";
    const serviceRegistryL2PolygonAddress = "0xE3607b00E75f6405248323A9417ff6b39B244b50";
    const serviceRegistryL2GnosisAddress = "0x9338b5153AE39BB89f50468E608eD9d764B755fD";
    const serviceRegistryTokenUtilityGnosisAddress = "0xa45E64d13A30a51b91ae0eb182e88a40e9b18eD8";
    const guardCMAddress = parsedData.guardCMAddress;
    const AMBContractProxyForeignAddress = "0x4C36d2919e407f0Cc2Ee3c993ccF8ac26d9CE64e";
    const homeMediatorAddress = "0x15bd56669F57192a97dF41A2aa8f4403e9491776";
    const fxRootAddress = parsedData.fxRootAddress;
    const fxGovernorTunnelAddress = "0x9338b5153AE39BB89f50468E608eD9d764B755fD";



    // Obtaining proposal values
    console.log("Guard CM setup");
    const guardCM = await ethers.getContractAt("GuardCM", guardCMAddress);
    const targets = [guardCMAddress, guardCMAddress];
    const values = new Array(2).fill(0);
    const callDatas = [
        guardCM.interface.encodeFunctionData("setBridgeMediatorChainIds", [[AMBContractProxyForeignAddress, fxRootAddress],
            [homeMediatorAddress, fxGovernorTunnelAddress], ["100", "137"]]),
        guardCM.interface.encodeFunctionData("setTargetSelectorChainIds", [[treasuryAddress, treasuryAddress, depositoryAddress,
            serviceRegistryTokenUtilityAddress, serviceRegistryL2PolygonAddress, serviceRegistryL2GnosisAddress,
            serviceRegistryTokenUtilityGnosisAddress],
        ["0x8456cb59", "0x8f202bf9", "0x58d3ec6a", "0xece53132", "0x9890220b", "0x9890220b", "0xece53132"],
        [1, 1, 1, 1, 137, 100, 100],
        [true, true, true, true, true, true, true]])
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
