const { execSync } = require("child_process");
const fs = require("fs");

// Function to get all Solidity files in a directory
function getSolidityFiles(directory) {
    try {
        return fs.readdirSync(directory).filter(file => file.endsWith(".sol"));
    } catch (error) {
        console.error(`Error reading directory ${directory}:`, error);
        return [];
    }
}

// Output file path
const outputFilePath = "scripts/analyzers/code_line_report.txt";

// Function to run cloc for a contract and extract code lines
function getCodeLines(contractPath) {
    try {
        const output = execSync(`cloc --csv --quiet --include-lang=solidity ${contractPath}`).toString();
        const lines = output.split("\n");
        if (lines.length >= 3) {
            const codeLine = lines[2].split(",")[4]; // Assuming the code line count is in the 5th column
            return parseInt(codeLine);
        }
    } catch (error) {
        console.error(`Error running cloc for ${contractPath}:`, error);
        return 0; // Return 0 in case of error
    }
    return 0; // Return 0 if lines.length < 3
}

// Function to write report to file
function writeReportToFile(report) {
    try {
        fs.writeFileSync(outputFilePath, report, "utf-8");
        console.log(`Report has been written to ${outputFilePath}`);
    } catch (error) {
        console.error("Error writing report to file:", error);
    }
}

// Main function to generate report
function generateReport() {
    let report = " ".padStart(6) + "| Contract".padEnd(123) + "|   CodeLine |\n";
    report += "-".repeat(142) + "\n";
    
    let totalCodeLines = 0;
    let contractNumber = 1;
    
    // Dynamically included contracts in contracts/staking/ directory
    const BridgeDir = "contracts/multisigs/bridge_verifier/";
    const solidityFilesInBridgeDir = getSolidityFiles(BridgeDir);
    solidityFilesInBridgeDir.forEach(contractName => {
        const contractPath = BridgeDir + contractName;
        const codeLines = getCodeLines(contractPath);
        report += `${contractNumber.toString().padStart(5)} | ${contractName.padEnd(120)} | ${codeLines.toString().padStart(10)} |\n`;
        totalCodeLines += codeLines;
        contractNumber++;
    }); 

    // Manually specified contracts in contracts/ directory
    const contractsInContractsDir = [
        "multisigs/GuardCM.sol",
        "multisigs/VerifyData.sol",
        "VoteWeighting.sol"

    ];

    contractsInContractsDir.forEach(contractName => {
        const contractPath = "contracts/" + contractName;
        const codeLines = getCodeLines(contractPath);
        report += `${contractNumber.toString().padStart(5)} | ${contractPath.padEnd(120)} | ${codeLines.toString().padStart(10)} |\n`;
        totalCodeLines += codeLines;
        contractNumber++;
    });
    
    //Add separator 
    report += "-".repeat(142) + "\n";
    // Add a row for all tokenomics contracts
    report += `${(contractNumber - 1).toString().padStart(5)} | All Governance contracts`.padEnd(128) + ` | ${totalCodeLines.toString().padStart(10)} |\n`;

    writeReportToFile(report);
}

// Generate report
generateReport();
