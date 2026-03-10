const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const timelockAddress = parsedData.timelockAddress;
const CM = parsedData.CM;
const governorAddress = parsedData.governorAddress;

module.exports = [
    timelockAddress,
    CM,
    governorAddress,
];