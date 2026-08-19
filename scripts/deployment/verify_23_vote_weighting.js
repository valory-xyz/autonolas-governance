const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);

// The dispenser is immutable and part of the constructor args, so verification must encode the
// exact address the contract was deployed with. Mirror the deploy scripts and refuse a
// missing/zero dispenser rather than silently encoding the zero address.
// dispenserAddress here must be the same value used at deployment time, i.e. the
// `dispenserProxyAddress` copied from the autonolas-tokenomics globals for this network.
const zeroAddress = "0x0000000000000000000000000000000000000000";
if (!parsedData.dispenserAddress || parsedData.dispenserAddress === zeroAddress) {
    throw new Error("dispenserAddress is not set (or is the zero address) in " + globalsFile +
        "; VoteWeighting binds the dispenser immutably — cannot verify with no dispenser");
}

module.exports = [
    parsedData.veOLASAddress,
    parsedData.dispenserAddress
];
