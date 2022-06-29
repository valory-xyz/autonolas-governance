const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const proposers = [parsedData.CM];
const executors = [parsedData.CM];

module.exports = [
    parsedData.timelockMinDelay,
    proposers,
    executors
];