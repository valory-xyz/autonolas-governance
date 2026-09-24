// Offline decode of raw_logs.json into a timeline. Fetches block timestamps and CM Safe tx inputs (read-only).
// Usage (from repo root): node audits/2026-09-22-governance-review/onchain/decode_logs.js [rpcUrl]
const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

const RPC = process.argv[2] || "https://gateway.tenderly.co/public/mainnet";
const DATA = path.join(__dirname, "data");
const ROOT = path.join(__dirname, "../../..");
const abi = f => require(path.join(ROOT, "abis", f)).abi;

const fragments = [
    ...abi("0.8.15/Timelock.json"), ...abi("0.8.30/GovernorOLAS.json"), ...abi("0.8.20/GovernorOLAS.json"),
    ...abi("0.8.30/GuardCM.json"), ...abi("0.8.23/GuardCM.json"),
    "event OwnerUpdated(address indexed owner)",
    "event ExecutionSuccess(bytes32 txHash, uint256 payment)",
    "event ExecutionFailure(bytes32 txHash, uint256 payment)",
    "event ChangedGuard(address guard)",
    "event AddedOwner(address owner)",
    "event RemovedOwner(address owner)",
    "event ChangedThreshold(uint256 threshold)",
    "event EnabledModule(address module)",
    "event DisabledModule(address module)",
    "event ChangedFallbackHandler(address handler)",
    "event SafeReceived(address indexed sender, uint256 value)",
    "event ApproveHash(bytes32 indexed approvedHash, address indexed owner)",
    "event SignMsg(bytes32 indexed msgHash)",
    "event ExecutionFromModuleSuccess(address indexed module)",
    "event ExecutionFromModuleFailure(address indexed module)",
];
// Deduplicate by signature so ethers accepts the merged interface.
const seen = new Set();
const events = new ethers.utils.Interface(fragments).fragments.filter(f => f.type === "event")
    .filter(f => { const s = f.format(); if (seen.has(s)) return false; seen.add(s); return true; });
const iface = new ethers.utils.Interface(events);
const safeIface = new ethers.utils.Interface([
    "function execTransaction(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,bytes signatures)",
]);

function plain(v) {
    if (ethers.BigNumber.isBigNumber(v)) return v.toString();
    if (Array.isArray(v)) return v.map(plain);
    return v;
}

async function main() {
    const raw = JSON.parse(fs.readFileSync(path.join(DATA, "raw_logs.json")));
    const label = Object.fromEntries(Object.entries(raw.addresses).map(([k, v]) => [v.toLowerCase(), k]));
    const provider = new ethers.providers.StaticJsonRpcProvider(RPC, 1);
    const blocks = {};
    for (const b of [...new Set(raw.logs.map(l => l.blockNumber))]) {
        blocks[b] = (await provider.send("eth_getBlockByNumber", [b, false])).timestamp;
    }
    const rows = [];
    for (const l of raw.logs) {
        let name = "unknown:" + l.topics[0], args = { topics: l.topics, data: l.data };
        try {
            const p = iface.parseLog(l);
            name = p.name;
            args = Object.fromEntries(p.eventFragment.inputs.map((inp, i) => [inp.name, plain(p.args[i])]));
        } catch (e) { /* keep raw */ }
        rows.push({ block: parseInt(l.blockNumber, 16), time: new Date(parseInt(blocks[l.blockNumber], 16) * 1000).toISOString(),
            tx: l.transactionHash, logIndex: parseInt(l.logIndex, 16), contract: label[l.address.toLowerCase()] || l.address, event: name, args });
    }
    // Attach the Safe call the CM executed (outer target, value, operation, selector).
    for (const r of rows.filter(r => r.contract === "cm" && /^Execution(Success|Failure)$/.test(r.event))) {
        const tx = await provider.getTransaction(r.tx);
        try {
            const d = safeIface.decodeFunctionData("execTransaction", tx.data);
            r.safeCall = { to: d.to, value: d.value.toString(), operation: d.operation, data: d.data };
        } catch (e) { r.safeCall = { note: "not a direct execTransaction", to: tx.to, input: tx.data.slice(0, 10) }; }
    }
    rows.sort((a, b) => a.block - b.block || a.logIndex - b.logIndex);
    fs.writeFileSync(path.join(DATA, "timeline.json"), JSON.stringify(rows, null, 1));
    const counts = {};
    for (const r of rows) counts[r.contract + "." + r.event] = (counts[r.contract + "." + r.event] || 0) + 1;
    console.log(JSON.stringify(counts, null, 1));
}

main().catch(e => { console.error(e); process.exit(1); });
