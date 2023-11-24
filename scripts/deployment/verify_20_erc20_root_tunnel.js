const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);

module.exports = [
    parsedData.checkpointManagerAddress,
    parsedData.fxRootAddress,
    parsedData.childTokenAddress,
    parsedData.bridgedERC20Address
];