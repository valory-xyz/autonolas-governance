/*global process, __dirname*/
// Generates a self-contained, collapsible HTML breakdown of proposal 18.
// It DECODES the authoritative calldata produced by the Forge builder (calldata.json), so the
// artifact cannot drift from what is voted.
//
// Usage (from repo root):
//   forge script scripts/proposals/proposal_18/Proposal18.s.sol:Proposal18 --sig "run()" > /tmp/run.txt
//   # (calldata.json already committed; regenerate it from the entry blocks if the builder changes)
//   node scripts/proposals/proposal_18/annotate.js "Proposal 18 — protocol maintenance"
// Writes proposal_18.html next to this script.

const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

const abi = ethers.utils.defaultAbiCoder;
const lc = (a) => (a || "").toLowerCase();

const ADDR = {
    "0x5650300fcbab43a0d7d02f8cb5d0f039402593f0": { label: "Dispenser (Ethereum)", chain: 1 },
    "0xc0b146d61e2a2c17e024477e01978d1fcf598c6b": { label: "GuardCM (community-multisig guard)", chain: 1 },
    "0x78bd94f48cae623cc74828ecbfebe3bdf428d83d": { label: "Dispenser proxy", chain: 1 },
    "0x1ac1181fc4e4f877963680587aeaa2c90d7ebb95": { label: "Celo L1 cross-domain messenger (L1 entrypoint for Celo)", chain: 1 },
    "0xc14e191a64a7fb0e5790a8a0b9a58683dffce04d": { label: "Celo governance mediator (OptimismMessenger)", chain: 42220 },
    "0xe3607b00e75f6405248323a9417ff6b39b244b50": { label: "ServiceRegistryL2 (Celo)", chain: 42220 },
    "0x63e66d7ad413c01a7b49c7ff4e3bb765c4e4bd1b": { label: "superseded GnosisSafe service-creation wrapper (Celo)", chain: 42220 },
};

const SELSIG = {
    "0x63096509": "setPauseState(uint8)",
    "0x5d78d469": "setTargetSelectorChainIds(address[],bytes4[],uint256[],bool[])",
    "0x3dbb202b": "sendMessage(address,bytes,uint32)",
    "0x82694b1d": "changeMultisigPermission(address,bool)",
};
const INNER_SEL = {
    "0x8456cb59": "pause()",
    "0x63096509": "setPauseState(uint8)",
    "0x82694b1d": "changeMultisigPermission(address,bool)",
};
const PAUSE_STATE = { "0": "Unpaused", "1": "DevIncentivesPaused", "2": "StakingIncentivesPaused", "3": "AllPaused" };
const EXPLORER = { 1: "https://etherscan.io/address/", 42220: "https://celoscan.io/address/" };

const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const addrSpan = (a) => {
    const e = ADDR[lc(a)];
    const url = (EXPLORER[e ? e.chain : 1] || EXPLORER[1]) + a;
    const lbl = e
        ? ` <span class="lbl">// ${esc(e.label)}</span>`
        : " <span class=\"warn\">// UNLABELLED — verify before voting</span>";
    return `<a class="addr" href="${url}" target="_blank" rel="noopener">${esc(a)}</a>${lbl}`;
};

function decodeInnerCall(target, data) {
    const isel = data.slice(0, 10);
    const isig = SELSIG[isel] || INNER_SEL[isel];
    let row = `${addrSpan(target)}<br>&nbsp;&nbsp;<span class="sel">${esc(isel)}</span> <span class="lbl">// ${esc(isig || "UNKNOWN")}</span>`;
    if (isel === "0x82694b1d") {
        const [m, b] = abi.decode(["address", "bool"], "0x" + data.slice(10));
        row += `<br>&nbsp;&nbsp;multisig ${addrSpan(m)}<br>&nbsp;&nbsp;permission <span class="val">${b}</span> <span class="lbl">// revoke</span>`;
    }
    return row;
}

function decodeEntry(e) {
    const sel = e.calldata.slice(0, 10);
    const sig = SELSIG[sel];
    if (!sig) return { sel, sig: null, rows: [[`<span class="warn">UNKNOWN SELECTOR ${esc(sel)} — do not vote until identified</span>`, ""]] };
    const types = sig.slice(sig.indexOf("(") + 1, -1).split(",");
    const decoded = abi.decode(types, "0x" + e.calldata.slice(10));
    const rows = [];
    if (sel === "0x63096509") {
        const st = decoded[0].toString();
        rows.push(["pauseState", `<span class="val">${st}</span> <span class="lbl">// ${PAUSE_STATE[st] || "?"}</span>`]);
    } else if (sel === "0x5d78d469") {
        for (let i = 0; i < decoded[0].length; i++) {
            const s = decoded[1][i];
            rows.push([
                `row[${i}]`,
                `${addrSpan(decoded[0][i])}<br>&nbsp;&nbsp;selector <span class="sel">${esc(s)}</span> <span class="lbl">// ${esc(INNER_SEL[s] || "UNKNOWN")}</span>` +
                `<br>&nbsp;&nbsp;chainId <span class="val">${decoded[2][i].toString()}</span>&nbsp;&nbsp;status <span class="val">${decoded[3][i]}</span> <span class="lbl">// ${decoded[3][i] ? "grant" : "revoke"}</span>`,
            ]);
        }
    } else if (sel === "0x3dbb202b") {
        const messenger = decoded[0], inner = decoded[1], gas = decoded[2];
        rows.push(["bridge", `OP-stack <code>sendMessage</code> &rarr; ${addrSpan(messenger)}`]);
        rows.push(["gas forwarded", `<span class="val">${gas.toString()}</span>`]);
        // inner = processMessageFromSource(bytes); unpack the packed (target, uint96 value, uint32 len, data) buffer
        const [payload] = abi.decode(["bytes"], "0x" + inner.slice(10));
        let p = payload.slice(2);
        let idx = 0;
        while (p.length >= 72) {
            const tgt = "0x" + p.slice(0, 40);
            const len = parseInt(p.slice(64, 72), 16);
            const data = "0x" + p.slice(72, 72 + len * 2);
            rows.push([`bridged call[${idx}]`, decodeInnerCall(tgt, data)]);
            p = p.slice(72 + len * 2);
            idx++;
        }
    }
    return { sel, sig, rows };
}

const title = process.argv[2] || "Proposal 18 — protocol maintenance";
const dir = __dirname;
const entries = JSON.parse(fs.readFileSync(path.join(dir, "calldata.json"), "utf8"));
const description = fs.readFileSync(path.join(dir, "description.txt"), "utf8");

const targets = entries.map((e) => e.target);
const values = entries.map((e) => e.value);
const calldatas = entries.map((e) => e.calldata);
const descriptionHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(description));
const proposalId = ethers.utils.keccak256(
    abi.encode(["address[]", "uint256[]", "bytes[]", "bytes32"], [targets, values, calldatas, descriptionHash])
);

const body = entries
    .map((e) => {
        const d = decodeEntry(e);
        return `<details open><summary>entry ${e.index} &mdash; <code>${esc(d.sig || d.sel)}</code></summary>
<table>
<tr><th>target</th><td>${addrSpan(e.target)}</td></tr>
<tr><th>value</th><td><span class="val">${esc(e.value)}</span></td></tr>
${d.rows.map(([k, v]) => `<tr><th>${esc(k)}</th><td>${v}</td></tr>`).join("\n")}
<tr><th>calldata</th><td><code class="cd">${esc(e.calldata)}</code></td></tr>
</table></details>`;
    })
    .join("\n");

const html = `<!doctype html><meta charset="utf-8"><title>${esc(title)}</title>
<style>
:root{--bg:#fff;--fg:#1a1a1a;--mut:#666;--acc:#0b5;--warnc:#b00;--line:#e3e3e3;--code:#f6f6f6}
@media(prefers-color-scheme:dark){:root{--bg:#121212;--fg:#e8e8e8;--mut:#9a9a9a;--acc:#4c9;--warnc:#f77;--line:#333;--code:#1c1c1c}}
body{background:var(--bg);color:var(--fg);font:14px/1.55 system-ui,-apple-system,"Segoe UI",sans-serif;margin:0 auto;padding:2rem 1.25rem;max-width:60rem}
h1{font-size:1.35rem;margin:0 0 .4rem}
table{border-collapse:collapse;width:100%;margin:.5rem 0 1rem}
th,td{border-bottom:1px solid var(--line);padding:.35rem .5rem;text-align:left;vertical-align:top}
th{width:13rem;color:var(--mut);font-weight:600;white-space:nowrap}
code,.addr,.sel,.val{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.86em}
.cd{display:block;overflow-wrap:anywhere;background:var(--code);padding:.5rem;border-radius:4px}
.addr{color:var(--acc);text-decoration:none}.addr:hover{text-decoration:underline}
.lbl{color:var(--mut)}.warn{color:var(--warnc);font-weight:600}
.box{border-left:3px solid var(--acc);background:var(--code);padding:.6rem .9rem;margin:1rem 0;border-radius:0 4px 4px 0}
details{border:1px solid var(--line);border-radius:6px;padding:.5rem .75rem;margin:.75rem 0}
summary{cursor:pointer;font-weight:600}
.meta{color:var(--mut);font-size:.9em}
pre{white-space:pre-wrap;overflow-wrap:anywhere;background:var(--code);padding:.75rem;border-radius:4px}
</style>
<h1>${esc(title)}</h1>
<p class="meta">Generated from <code>calldata.json</code> &mdash; the same bytes the Forge builder emits, decoded rather than re-encoded.</p>

<div class="box">Entries 0 and 1 are <strong>direct Ethereum</strong> Timelock calls: (0) pause the Dispenser's staking-incentive
distribution; (1) one atomic GuardCM update that grants the community-multisig guard the <code>pause()</code> selector on the
new Dispenser proxy <em>and</em> revokes its <code>setPauseState(uint8)</code> selector on the old Dispenser, so the community
multisig cannot reopen the paused claim path. Entry 2 is <strong>bridged to Celo</strong> through the OP-stack cross-domain
messenger and executed by the Celo governance mediator (revoke a superseded service-creation wrapper permission). Total ETH
value is <strong>0</strong>.</div>

<table>
<tr><th>proposalId</th><td><code>${proposalId}</code></td></tr>
<tr><th>proposalId (uint)</th><td><code>${ethers.BigNumber.from(proposalId).toString()}</code></td></tr>
<tr><th>descriptionHash</th><td><code>${descriptionHash}</code></td></tr>
<tr><th>entries</th><td><span class="val">${entries.length}</span> &mdash; 2 direct L1, 1 bridged (Celo)</td></tr>
<tr><th>total value</th><td><span class="val">0</span> wei</td></tr>
</table>

${body}

<details><summary>propose() arrays</summary>
<pre>targets:    ${esc(JSON.stringify(targets, null, 2))}

values:     ${esc(JSON.stringify(values))}

calldatas:  ${esc(JSON.stringify(calldatas, null, 2))}</pre></details>

<details><summary>description (must match the builder constant byte-for-byte)</summary>
<pre>${esc(description)}</pre></details>
`;

const outPath = path.join(dir, path.basename(dir) + ".html");
fs.writeFileSync(outPath, html);
console.log("wrote", outPath);
console.log("proposalId    ", proposalId);
console.log("descriptionHash", descriptionHash);
