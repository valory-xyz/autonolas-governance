/*global process, __dirname*/
// Generates a self-contained, collapsible HTML breakdown of proposal 16 (Robinhood Chain wave 2).
// It DECODES the authoritative calldata produced by the Forge builder (calldata.json, parsed from the
// builder's run() output), so the artifact cannot drift from what is voted.
//
// Usage (from repo root):
//   forge script scripts/proposals/proposal_16/Proposal16Robinhood.s.sol:Proposal16Robinhood > /tmp/run.txt
//   # parse the [--- entry N ---/target/value/calldata] blocks into proposal_16/calldata.json, then:
//   node scripts/proposals/proposal_16/annotate.js "Proposal 16 — Olas on Robinhood Chain: wave 2"
// Writes proposal_16.html next to this script.

const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

const abi = ethers.utils.defaultAbiCoder;
const lc = (a) => (a || "").toLowerCase();

// Every address in this proposal is either on Ethereum or on Robinhood Chain (4663). Unlike
// proposal 13 there is no deployer-nonce collision *within* this proposal, but two constants are
// deliberately shared with the Arbitrum One route and will look like mistakes on review:
//   0x4d30F68F… is alias(L1 Timelock) and is the SAME on every Orbit chain, Arbitrum One included.
//   0x0F336366… is the single Orbit bridge-data verifier, reused across Orbit chains by design.
const ADDR = {
    "0x5650300fcbab43a0d7d02f8cb5d0f039402593f0": { label: "Dispenser", chain: 1 },
    "0xc0b146d61e2a2c17e024477e01978d1fcf598c6b": { label: "GuardCM", chain: 1 },
    "0x3c1ff68f5aa342d296d4dee4bb1cacca912d95fe": { label: "Timelock", chain: 1 },
    "0x1a07cc4bd17e0118bdb54d70990d2158abad7a2d": { label: "Robinhood Chain Delayed Inbox (L1 entrypoint for 4663)", chain: 1 },
    "0x0f33636698f6607b2fddc1e857788535914c44d4": { label: "ProcessBridgedDataArbitrum (Orbit verifier — shared with Arbitrum One by design)", chain: 1 },
    "0xb9dfcc6155ba4f211dcf8e6ecc9976be11bb7a77": { label: "ArbitrumDepositProcessorL1 for 4663 (l2TargetChainId() == 4663)", chain: 1 },
    "0x4d30f68f5aa342d296d4dee4bb1cacca912da70f": { label: "alias(Timelock) — 4663 bridge mediator. SAME address as Arbitrum One's by design", chain: 4663 },
    "0x63e66d7ad413c01a7b49c7ff4e3bb765c4e4bd1b": { label: "ServiceManagerProxy (4663)", chain: 4663 },
    "0xc40c79c275f3fa1f3f4c723755c81ed2d53a8d81": { label: "ArbitrumTargetDispenserL2 (4663)", chain: 4663 },
    "0xe3607b00e75f6405248323a9417ff6b39b244b50": { label: "ServiceRegistryL2 (4663)", chain: 4663 },
    "0x3d77596beb0f130a4415df3d2d8232b3d3d31e44": { label: "ServiceRegistryTokenUtility (4663)", chain: 4663 },
};

const SELSIG = {
    "0xd8bf69bf": "setDepositProcessorChainIds(address[],uint256[])",
    "0x1602c55c": "setBridgeMediatorL1BridgeParams(address[],address[],uint256[],address[])",
    "0x5d78d469": "setTargetSelectorChainIds(address[],bytes4[],uint256[],bool[])",
};
const INNER_SEL = {
    "0x8456cb59": "pause()",
    "0x9890220b": "drain()",
    "0xece53132": "drain(address)",
    // unpause() is listed so a reviewer sees it named if it ever reappears — it is allowlisted on
    // no chain, and this proposal deliberately does not grant it.
    "0x3f4ba83a": "unpause() — NOT granted on any chain",
};
const EXPLORER = { 1: "https://etherscan.io/address/", 4663: "https://robinhoodchain.blockscout.com/address/" };

const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const addrSpan = (a) => {
    const e = ADDR[lc(a)];
    const url = (EXPLORER[e ? e.chain : 1] || EXPLORER[1]) + a;
    const lbl = e
        ? ` <span class="lbl">// ${esc(e.label)}</span>`
        : " <span class=\"warn\">// UNLABELLED — verify before voting</span>";
    return `<a class="addr" href="${url}" target="_blank" rel="noopener">${esc(a)}</a>${lbl}`;
};

function decodeEntry(e) {
    const sel = e.calldata.slice(0, 10);
    const sig = SELSIG[sel];
    if (!sig) return { sel, sig: null, rows: [[`<span class="warn">UNKNOWN SELECTOR ${esc(sel)} — do not vote until identified</span>`, ""]] };
    const types = sig.slice(sig.indexOf("(") + 1, -1).split(",");
    const decoded = abi.decode(types, "0x" + e.calldata.slice(10));
    const rows = [];
    if (sel === "0xd8bf69bf") {
        rows.push(["depositProcessors[0]", addrSpan(decoded[0][0])]);
        rows.push(["chainIds[0]", `<span class="val">${decoded[1][0].toString()}</span> <span class="lbl">// Robinhood Chain</span>`]);
    } else if (sel === "0x1602c55c") {
        rows.push(["bridgeMediatorL1[0]", addrSpan(decoded[0][0])]);
        rows.push(["verifierL2[0]", addrSpan(decoded[1][0])]);
        rows.push(["chainId[0]", `<span class="val">${decoded[2][0].toString()}</span>`]);
        rows.push(["bridgeMediatorL2[0]", addrSpan(decoded[3][0])]);
    } else {
        for (let i = 0; i < decoded[0].length; i++) {
            const s = decoded[1][i];
            rows.push([
                `triple[${i}]`,
                `${addrSpan(decoded[0][i])}<br>&nbsp;&nbsp;selector <span class="sel">${esc(s)}</span> <span class="lbl">// ${esc(INNER_SEL[s] || "UNKNOWN")}</span>` +
                `<br>&nbsp;&nbsp;chainId <span class="val">${decoded[2][i].toString()}</span>` +
                `&nbsp;&nbsp;status <span class="val">${decoded[3][i]}</span>`,
            ]);
        }
    }
    return { sel, sig, rows };
}

const title = process.argv[2] || "Proposal 16 — Olas on Robinhood Chain: wave 2";
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
.box{border-left:3px solid var(--warnc);background:var(--code);padding:.6rem .9rem;margin:1rem 0;border-radius:0 4px 4px 0}
details{border:1px solid var(--line);border-radius:6px;padding:.5rem .75rem;margin:.75rem 0}
summary{cursor:pointer;font-weight:600}
.meta{color:var(--mut);font-size:.9em}
pre{white-space:pre-wrap;overflow-wrap:anywhere;background:var(--code);padding:.75rem;border-radius:4px}
</style>
<h1>${esc(title)}</h1>
<p class="meta">Generated from <code>calldata.json</code> &mdash; the same bytes the Forge builder emits, decoded rather than re-encoded.</p>

<div class="box"><strong class="warn">Address collision, expected &mdash; do not &ldquo;fix&rdquo; it.</strong><br>
<code>0x4d30F68F&hellip;</code> (the 4663 bridge mediator) is <em>byte-identical</em> to Arbitrum One's mediator, and
<code>0x0F336366&hellip;</code> (the verifier) is shared with the Arbitrum One route. Both are correct: on every Orbit chain
the L2 governance sender is <code>alias(L1&nbsp;Timelock)</code>, and the aliasing rule is chain-independent, so two Orbit
chains aliasing the same Timelock yield the same address. One verifier contract serves all Orbit chains. Only the
<em>inbox</em> and the <em>chain Id</em> distinguish this route from Arbitrum One's.</div>

<table>
<tr><th>proposalId</th><td><code>${proposalId}</code></td></tr>
<tr><th>proposalId (uint)</th><td><code>${ethers.BigNumber.from(proposalId).toString()}</code></td></tr>
<tr><th>descriptionHash</th><td><code>${descriptionHash}</code></td></tr>
<tr><th>entries</th><td><span class="val">${entries.length}</span> &mdash; all direct L1 calls, no bridged payload</td></tr>
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
