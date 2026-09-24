// Read-only: fetch raw mainnet logs for governance addresses over the area-0 window.
// Usage (from repo root): node audits/2026-09-22-governance-review/onchain/collect_logs.js [rpcUrl]
const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

const RPC = process.argv[2] || "https://gateway.tenderly.co/public/mainnet";
const FROM = 24577960; // first block at/after baseline commit 2026-03-03T15:55:58Z
const TO = 26032401;   // head at collection, 2026-09-22
const STEP = 200000; // public Tenderly gateway accepts wide ranges; chunked to bound response size
const OUT = path.join(__dirname, "data");

const ADDRESSES = {
    timelock: "0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE",
    governorOne: "0x34C895f302D0b5cf52ec0Edd3945321EB0f83dd5",
    governorTwo: "0x8E84B5055492901988B831817e4Ace5275A3b401",
    governor: "0x060D0CBdDFb0498d610E2EF55C01516B5B1251E6",
    guardCMOld: "0x7bB7998b210cFfE10ca1e41f16341Abe53f76f3a",
    guardCM: "0xC0b146D61e2A2C17E024477E01978D1Fcf598c6B",
    cm: "0x04C06323Fe3D53Deb7364c0055E1F68458Cc2570",
};
// Treasury emits many events; only ownership changes are needed.
const TREASURY = "0xa0DA53447C0f6C4987964d8463da7e6628B30f82";
const OWNER_UPDATED = ethers.utils.id("OwnerUpdated(address)");

async function withRetry(fn) {
    for (let i = 0; ; i++) {
        try { return await fn(); } catch (e) {
            if (i >= 6) throw e;
            await new Promise(r => setTimeout(r, 2000 * (i + 1)));
        }
    }
}

async function main() {
    fs.mkdirSync(OUT, { recursive: true });
    const provider = new ethers.providers.StaticJsonRpcProvider(RPC, 1);
    const logs = [];
    for (let from = FROM; from <= TO; from += STEP) {
        const to = Math.min(from + STEP - 1, TO);
        const [a, b] = await Promise.all([
            withRetry(() => provider.send("eth_getLogs", [{ address: Object.values(ADDRESSES),
                fromBlock: ethers.utils.hexValue(from), toBlock: ethers.utils.hexValue(to) }])),
            withRetry(() => provider.send("eth_getLogs", [{ address: TREASURY, topics: [OWNER_UPDATED],
                fromBlock: ethers.utils.hexValue(from), toBlock: ethers.utils.hexValue(to) }])),
        ]);
        logs.push(...a, ...b);
        process.stderr.write(`${to} ${logs.length}\n`);
    }
    fs.writeFileSync(path.join(OUT, "raw_logs.json"), JSON.stringify({ rpc: RPC, from: FROM, to: TO,
        addresses: { ...ADDRESSES, treasury: TREASURY }, logs }, null, 1));
}

main().catch(e => { console.error(e); process.exit(1); });
