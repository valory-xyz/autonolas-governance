const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);

module.exports = [
    parsedData.veOLASAddress,
    parsedData.dispenserAddress || "0x0000000000000000000000000000000000000000"
];
