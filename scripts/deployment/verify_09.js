const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const initialVotingDelay = parsedData.initialVotingDelay;
const initialVotingPeriod = parsedData.initialVotingPeriod;
const initialProposalThreshold = parsedData.initialProposalThreshold;
const quorum = parsedData.quorum;

module.exports = [
    parsedData.veOLASAddress,
    parsedData.timelockAddress,
    initialVotingDelay,
    initialVotingPeriod,
    initialProposalThreshold,
    quorum
];