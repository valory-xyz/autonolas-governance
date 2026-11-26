/*global process, __dirname*/
// Generates a self-contained, collapsible HTML breakdown of proposal 20.
// It DECODES the authoritative calldata produced by the Forge builder (calldata.json), so the
// artifact cannot drift from what is voted.
//
// Usage (from repo root):
//   forge script scripts/proposals/proposal_20/Proposal20.s.sol:Proposal20 --sig "run()" > /tmp/run.txt
//   # (calldata.json already committed; regenerate it from the entry blocks if the builder changes)
//   node scripts/proposals/proposal_20/annotate.js "Proposal 20 — protocol maintenance"
// Writes proposal_20.html next to this script.

const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

const abi = ethers.utils.defaultAbiCoder;
const lc = (a) => (a || "").toLowerCase();

const ADDR = {
    "0xc096362fa6f4a4b1a9ea68b1043416f3381ce300": { label: "Tokenomics (Ethereum)", chain: 1 },
    "0xa0da53447c0f6c4987964d8463da7e6628b30f82": { label: "Treasury (Ethereum)", chain: 1 },
    "0x78bd94f48cae623cc74828ecbfebe3bdf428d83d": { label: "Dispenser proxy (Ethereum)", chain: 1 },
};

const SELSIG = {
    "0xd5297793": "changeManagers(address,address,address)",
    "0x63096509": "setPauseState(uint8)",
};
// changeManagers has a different 1st parameter name on Tokenomics vs Treasury; the 3rd is the
// dispenser in both (zero args are skipped by the setter, leaving the other managers unchanged).
const MANAGER_ARGS = {
    "0xc096362fa6f4a4b1a9ea68b1043416f3381ce300": ["treasury", "depository", "dispenser"],
    "0xa0da53447c0f6c4987964d8463da7e6628b30f82": ["tokenomics", "depository", "dispenser"],
};
const PAUSE_STATE = { "0": "Unpaused", "1": "DevIncentivesPaused", "2": "StakingIncentivesPaused", "3": "AllPaused" };
const EXPLORER = { 1: "https://etherscan.io/address/" };

const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const addrSpan = (a) => {
    const e = ADDR[lc(a)];
    const url = (EXPLORER[e ? e.chain : 1] || EXPLORER[1]) + a;
    const lbl = e
        ? ` <span class="lbl">// ${esc(e.label)}</span>`
        : " <span class=\"warn\">// UNLABELLED — verify before voting</span>";
    return `<a class="addr" href="${url}" target="_blank" rel="noopener">${esc(a)}</a>${lbl}`;
};

const ZERO = "0x0000000000000000000000000000000000000000";

function decodeEntry(e) {
    const sel = e.calldata.slice(0, 10);
    const sig = SELSIG[sel];
    if (!sig) return { sel, sig: null, rows: [[`<span class="warn">UNKNOWN SELECTOR ${esc(sel)} — do not vote until identified</span>`, ""]] };
    const types = sig.slice(sig.indexOf("(") + 1, -1).split(",");
    const decoded = abi.decode(types, "0x" + e.calldata.slice(10));
    const rows = [];
    if (sel === "0xd5297793") {
        const names = MANAGER_ARGS[lc(e.target)] || ["arg0", "arg1", "dispenser"];
        for (let i = 0; i < 3; i++) {
            const v = decoded[i];
            if (lc(v) === ZERO) {
                rows.push([names[i], `<span class="val">${esc(v)}</span> <span class="lbl">// unchanged (zero)</span>`]);
            } else {
                rows.push([names[i], `${addrSpan(v)} <span class="lbl">// set</span>`]);
            }
        }
    } else if (sel === "0x63096509") {
        const st = decoded[0].toString();
        rows.push(["pauseState", `<span class="val">${st}</span> <span class="lbl">// ${PAUSE_STATE[st] || "?"}</span>`]);
    }
    return { sel, sig, rows };
}

const title = process.argv[2] || "Proposal 20 — protocol maintenance";
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

<div class="box">All three entries are <strong>direct Ethereum</strong> Timelock calls: (0) set the Tokenomics contract's
dispenser manager to the Dispenser proxy <code>0x78Bd94F4…</code>; (1) set the Treasury contract's dispenser manager to
the same proxy (which authorises it for treasury withdrawals); (2) set that Dispenser proxy's pause state to
<code>Unpaused</code>. In entries 0 and 1 the other manager arguments are passed as zero, so the setter leaves them
unchanged. Total ETH value is <strong>0</strong>.</div>

<table>
<tr><th>proposalId</th><td><code>${proposalId}</code></td></tr>
<tr><th>proposalId (uint)</th><td><code>${ethers.BigNumber.from(proposalId).toString()}</code></td></tr>
<tr><th>descriptionHash</th><td><code>${descriptionHash}</code></td></tr>
<tr><th>entries</th><td><span class="val">${entries.length}</span> &mdash; 3 direct L1</td></tr>
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
