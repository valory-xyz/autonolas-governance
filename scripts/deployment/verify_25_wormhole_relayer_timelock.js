const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);

module.exports = [
    parsedData.timelockAddress,
    parsedData.wormholeL1MessageRelayerAddress,
    parsedData.refundChainId
];