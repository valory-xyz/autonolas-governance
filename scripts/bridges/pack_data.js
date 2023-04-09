/*global process*/

const { ethers } = require("ethers");

async function main() {
    // Get the transaction data from file
    const fs = require("fs");
    const dataJSON = "transactions.json";
    const dataFromJSON = fs.readFileSync(dataJSON, "utf8");
    const parsedFile = JSON.parse(dataFromJSON);
    const targets = parsedFile["targets"];
    const values = parsedFile["values"];
    const payloads = parsedFile["payloads"];

    // Check for the input length correctness
    if (targets.length != values.length || targets.length != payloads.length) {
        console.log("Array sizes mismatch");
        return;
    }

    // Pack the data into one continuous buffer
    let data = "0x";
    for (let i = 0; i < targets.length; i++) {
        const payload = ethers.utils.arrayify(payloads[i]);
        const encoded = ethers.utils.solidityPack(
            ["address", "uint96", "uint32", "bytes"],
            [targets[i], values[i], payload.length, payload]
        );
        data += encoded.slice(2);
    }
    console.log(data);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
