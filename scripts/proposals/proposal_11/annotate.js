/*global process, __dirname*/
// Generates a self-contained, color-coded, collapsible HTML breakdown of the proposal 11
// activation proposal. It DECODES the authoritative calldata produced by the Forge builder
// (scripts/proposals/proposal_11/Proposal11Activation.s.sol), so the artifact cannot drift from
// what will be voted.
//
// Usage:
//   forge script scripts/proposals/proposal_11/Proposal11Activation.s.sol:Proposal11Activation > /tmp/run.txt
//   # extract [{index,target,value,calldata}] into calldata.json, then:
//   node scripts/proposals/proposal_11/annotate.js   (reads ./calldata.json + ./description.txt)
// Writes ./proposal_11.html next to this script.

const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

const id = ethers.utils.id;
const abi = ethers.utils.defaultAbiCoder;
const lc = (a) => (a || "").toLowerCase();

// ---- semantic label maps ----
const ADDR = {
    "0x3c1ff68f5aa342d296d4dee4bb1cacca912d95fe": "Timelock",
    "0x060d0cbddfb0498d610e2ef55c01516b5b1251e6": "NEW GovernorOLAS",
    "0x8e84b5055492901988b831817e4ace5275a3b401": "OLD GovernorOLAS",
    "0xc0b146d61e2a2c17e024477e01978d1fcf598c6b": "NEW GuardCM",
    "0x04c06323fe3d53deb7364c0055e1f68458cc2570": "Community Multisig (CM Safe)",
    "0x4c36d2919e407f0cc2ee3c993ccf8ac26d9ce64e": "Gnosis AMB (L1)",
    "0xfe5e5d361b2ad62c541bab87c45a0b9b018389a2": "Polygon FxRoot (L1)",
    "0x4dbd4fc535ac27206064b68ffcf827b0a60bab3f": "Arbitrum Inbox (L1)",
    "0x25ace71c97b33cc4729cf772ae268934f7ab5fa1": "Optimism L1CrossDomainMessenger",
    "0x866e82a600a1414e583f7f13623f1ac5d58b0afa": "Base L1CrossDomainMessenger",
    "0x1ac1181fc4e4f877963680587aeaa2c90d7ebb95": "Celo L1CrossDomainMessenger",
    "0xdc871b7833932d45023755c9de3786060a934c48": "ProcessBridgedDataGnosis (verifier)",
    "0x133a6d318fa0c9413a70c149e7f630015044dec3": "ProcessBridgedDataPolygon (verifier)",
    "0x0f33636698f6607b2fddc1e857788535914c44d4": "ProcessBridgedDataArbitrum (verifier)",
    "0xdcafcccc7ba0b7185a472d9d068fde0af4313fb5": "ProcessBridgedDataOptimism (verifier)",
    "0x15bd56669f57192a97df41a2aa8f4403e9491776": "HomeMediator (Gnosis L2)",
    "0x9338b5153ae39bb89f50468e608ed9d764b755fd": "FxGovernorTunnel (Polygon L2)",
    "0x4d30f68f5aa342d296d4dee4bb1cacca912da70f": "BridgeMediator (Arbitrum L2)",
    "0x87c511c8ae3faf0063b3f3cf9c6ab96c4aa5c60c": "OptimismMessenger (Optimism L2)",
    "0xe49cb081e8d96920c38aa7ab90cb0294ab4bc8ea": "OptimismMessenger (Base L2)",
    "0xc14e191a64a7fb0e5790a8a0b9a58683dffce04d": "OptimismMessenger (Celo L2)",
    "0xa0da53447c0f6c4987964d8463da7e6628b30f82": "Treasury",
    "0xff8697d8d2998d6aa2e09b405795c6f4beeb0c81": "Depository (LIVE)",
    "0x3fb926116d454b95c669b6bf2e7c3bad8d19affa": "ServiceRegistryTokenUtility (L1)",
    "0xc096362fa6f4a4b1a9ea68b1043416f3381ce300": "TokenomicsProxy",
    "0xaeec8bc8e5fe28bc4df2e9586b222924b8a0d5e9": "Tokenomics impl v1.4.3 (NEW)",
    "0x17d96ba4532fe91809326092fe4d5606a7b7a0d8": "MechMarketplaceProxy (Celo)",
    "0x2e008211f34b25a7d7c102403c6c2c3b665a1abe": "BalanceTracker Native (Celo, NEW)",
    "0xb3921f8d8215603f0bd521341ac45ea8f2d274c1": "BalanceTracker OLAS (Celo, NEW)",
    "0x97371b1c0cda1d04dfc43dfb50a04645b7bc9bee": "BalanceTracker USDC (Celo, NEW)",
};
const ROLE = {
    [id("TIMELOCK_ADMIN_ROLE")]: "TIMELOCK_ADMIN_ROLE",
    [id("PROPOSER_ROLE")]: "PROPOSER_ROLE",
    [id("EXECUTOR_ROLE")]: "EXECUTOR_ROLE",
    [id("CANCELLER_ROLE")]: "CANCELLER_ROLE",
};
const PTYPE = {
    "0xba699a34be8fe0e7725e93dcbce1701b0211a8ca61330aaeb8a05bf2ec7abed1": "FixedPriceNative",
    "0x3679d66ef546e66ce9057c4a052f317b135bc8e8c509638f7966edfd4fcf45e9": "FixedPriceToken (OLAS)",
    "0x6406bb5f31a732f898e1ce9fdd988a80a808d36ab5d9a4a4805a8be8d197d5e3": "FixedPriceTokenUSDC",
};
const SELSIG = {
    "0x2f2ff15d": "grantRole(bytes32,address)",
    "0xd547741f": "revokeRole(bytes32,address)",
    "0x1602c55c": "setBridgeMediatorL1BridgeParams(address[],address[],uint256[],address[])",
    "0x5d78d469": "setTargetSelectorChainIds(address[],bytes4[],uint256[],bool[])",
    "0x468721a7": "execTransactionFromModule(address,uint256,bytes,uint8)",
    "0xe19a9dd9": "setGuard(address)",
    "0x3dbb202b": "sendMessage(address,bytes,uint32)",
    "0xd3042d2b": "processMessageFromSource(bytes)",
    "0xd64bf8b0": "setPaymentTypeBalanceTrackers(bytes32[],address[])",
    "0x590a92d0": "changeTokenomicsImplementation(address)",
    "0x8456cb59": "pause()",
    "0x8f202bf9": "drainServiceSlashedFunds()",
    "0x58d3ec6a": "close(uint256[])",
    "0xece53132": "drain(address)",
    "0x9890220b": "drain()",
};
const CHAIN = { 1: "Ethereum", 100: "Gnosis", 137: "Polygon", 42161: "Arbitrum", 10: "Optimism", 8453: "Base", 42220: "Celo" };

// Per-row semantic labels for the C allowlist (avoids CREATE2 address-collision ambiguity)
const C_ROWS = [
    "Treasury", "Treasury", "Depository (LIVE)", "ServiceRegistryTokenUtility (L1)",
    "ServiceRegistryL2 (Gnosis)", "ServiceRegistryTokenUtility (Gnosis)",
    "ServiceRegistryL2 (Polygon)", "ServiceRegistryTokenUtility (Polygon)",
    "ServiceRegistryL2 (Arbitrum)", "ServiceRegistryTokenUtility (Arbitrum)",
    "ServiceRegistryL2 (Optimism)", "ServiceRegistryTokenUtility (Optimism)",
    "ServiceRegistryL2 (Base)", "ServiceRegistryTokenUtility (Base)",
    "ServiceRegistryL2 (Celo)", "ServiceRegistryTokenUtility (Celo)",
];

// Block explorer (address page) per chainId.
const EXPLORER = {
    1: "https://etherscan.io/address/",
    100: "https://gnosisscan.io/address/",
    137: "https://polygonscan.com/address/",
    42161: "https://arbiscan.io/address/",
    10: "https://optimistic.etherscan.io/address/",
    8453: "https://basescan.org/address/",
    42220: "https://celoscan.io/address/",
};

const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
// Renders an address as a link to the correct chain's explorer. chainId defaults to Ethereum (1).
const addrSpan = (a, chainId = 1) => {
    const cid = Number(chainId);
    const addr = ethers.utils.getAddress(a);
    const name = ADDR[lc(a)];
    const chainName = CHAIN[cid] || ("chain " + cid);
    const label = (name ? name + " · " : "") + chainName;
    const url = (EXPLORER[cid] || EXPLORER[1]) + addr + "#code"; // open the Contract Code tab -> name visible
    return `<a class="addr" href="${url}" target="_blank" rel="noopener" title="${esc(label)}">${esc(addr)}</a>` +
        ` <span class="note">// ${esc(label)}</span>`;
};
const selSpan = (sel) => {
    const sig = SELSIG[lc(sel)] || "unknown";
    return `<span class="sel" title="${esc(sig)}">${esc(sel)}</span> <span class="note">// ${esc(sig)}</span>`;
};
const roleSpan = (r) => `<span class="role">${esc(r)}</span> <span class="note">// ${esc(ROLE[lc(r)] || "role")}</span>`;
const ptypeSpan = (p) => `<span class="role">${esc(p)}</span> <span class="note">// ${esc(PTYPE[lc(p)] || "paymentType")}</span>`;
const valSpan = (v, note) => `<span class="val">${esc(v)}</span>` + (note ? ` <span class="note">// ${esc(note)}</span>` : "");

function row(name, html) { return `<div class="row"><span class="key">${esc(name)}</span> = ${html}</div>`; }
function callBox(title, inner, open = true) {
    return `<details class="call"${open ? " open" : ""}><summary>${title}</summary><div class="body">${inner}</div></details>`;
}

function decodeEntry(e) {
    const sel = e.calldata.slice(0, 10);
    const args = "0x" + e.calldata.slice(10);
    const head = `${selSpan(sel)}`;

    if (sel === "0x2f2ff15d" || sel === "0xd547741f") {
        const [role, account] = abi.decode(["bytes32", "address"], args);
        return callBox(head, row("role", roleSpan(role)) + row("account", addrSpan(account)));
    }
    if (sel === "0x1602c55c") {
        const [l1s, vs, cids, l2s] = abi.decode(["address[]", "address[]", "uint256[]", "address[]"], args);
        let inner = "";
        for (let i = 0; i < l1s.length; i++) {
            inner += callBox(`<span class="key">chain ${cids[i]} (${CHAIN[cids[i]] || "?"})</span>`,
                row("bridgeMediatorL1 (Ethereum)", addrSpan(l1s[i], 1)) + row("verifierL2 (on Ethereum)", addrSpan(vs[i], 1)) +
                row("chainId", valSpan(cids[i].toString(), CHAIN[cids[i]])) + row("bridgeMediatorL2", addrSpan(l2s[i], cids[i])), true);
        }
        return callBox(head, inner);
    }
    if (sel === "0x5d78d469") {
        const [t, s, c, st] = abi.decode(["address[]", "bytes4[]", "uint256[]", "bool[]"], args);
        let rows = "";
        for (let i = 0; i < t.length; i++) {
            const cid = Number(c[i]);
            const addr = ethers.utils.getAddress(t[i]);
            const url = (EXPLORER[cid] || EXPLORER[1]) + addr + "#code";
            rows += `<tr><td class="num">${i}</td><td>${C_ROWS[i] || "?"}</td>` +
                `<td><a class="addr" href="${url}" target="_blank" rel="noopener" title="${esc((C_ROWS[i] || "") + " · " + (CHAIN[cid] || cid))}">${esc(addr)}</a></td>` +
                `<td class="sel">${esc(s[i])}</td><td>${esc(SELSIG[lc(s[i])] || "")}</td>` +
                `<td>${c[i]} <span class="note">${esc(CHAIN[cid] || "")}</span></td>` +
                `<td>${st[i] ? "<span class=\"ok\">enable</span>" : "<span class=\"bad\">disable</span>"}</td></tr>`;
        }
        const table = `<table class="al"><thead><tr><th>#</th><th>target</th><th>address</th><th>selector</th><th>function</th><th>chain</th><th>status</th></tr></thead><tbody>${rows}</tbody></table>`;
        return callBox(head, table);
    }
    if (sel === "0x468721a7") {
        const [to, value, data, op] = abi.decode(["address", "uint256", "bytes", "uint8"], args);
        const innerSel = data.slice(0, 10);
        const [guard] = abi.decode(["address"], "0x" + data.slice(10));
        const nested = callBox(`${selSpan(innerSel)}`, row("guard", addrSpan(guard)), true);
        return callBox(head, row("to", addrSpan(to)) + row("value", valSpan(value.toString())) +
            row("operation", valSpan(op.toString(), op == 0 ? "Call" : "DelegateCall")) +
            "<div class=\"row\"><span class=\"key\">data</span> ⇣</div>" + nested);
    }
    if (sel === "0x3dbb202b") {
        const [target, message, minGas] = abi.decode(["address", "bytes", "uint32"], args);
        // message = processMessageFromSource(bytes)
        const pSel = message.slice(0, 10);
        const [packed] = abi.decode(["bytes"], "0x" + message.slice(10));
        const pk = packed.slice(2);
        const innerTarget = ethers.utils.getAddress("0x" + pk.slice(0, 40));
        const innerValue = ethers.BigNumber.from("0x" + pk.slice(40, 64)).toString();
        const payloadLen = parseInt(pk.slice(64, 72), 16);
        const payload = "0x" + pk.slice(72);
        const plSel = payload.slice(0, 10);
        const [pts, bts] = abi.decode(["bytes32[]", "address[]"], "0x" + payload.slice(10));
        let ptRows = "";
        for (let i = 0; i < pts.length; i++) ptRows += row(`paymentType[${i}]`, ptypeSpan(pts[i]));
        const CELO = 42220;
        let btRows = "";
        for (let i = 0; i < bts.length; i++) btRows += row(`balanceTracker[${i}]`, addrSpan(bts[i], CELO));
        const innerCall = callBox(`${selSpan(plSel)}`, ptRows + btRows, true);
        const packedBox = callBox("<span class=\"key\">packed bridge payload</span> <span class=\"note\">// target(20)|value(12)|len(4)|payload</span>",
            row("target", addrSpan(innerTarget, CELO)) + row("value", valSpan(innerValue)) +
            row("payloadLength", valSpan(payloadLen + " bytes")) +
            "<div class=\"row\"><span class=\"key\">payload</span> ⇣</div>" + innerCall, true);
        const procBox = callBox(`${selSpan(pSel)}`, packedBox, true);
        return callBox(head, row("_target (L2 receiver)", addrSpan(target, CELO)) +
            row("_minGasLimit", valSpan(minGas.toString())) +
            "<div class=\"row\"><span class=\"key\">_message</span> ⇣</div>" + procBox);
    }
    if (sel === "0x590a92d0") {
        const [impl] = abi.decode(["address"], args);
        return callBox(head, row("implementation", addrSpan(impl)));
    }
    return callBox(head, "<div class=\"row note\">unrecognized selector</div>");
}

// OZ Governor.hashProposal: uint256(keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description)))))
function computeProposalId(targets, values, calldatas, description) {
    const descHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(description));
    const encoded = abi.encode(["address[]", "uint256[]", "bytes[]", "bytes32"], [targets, values, calldatas, descHash]);
    return { id: ethers.BigNumber.from(ethers.utils.keccak256(encoded)).toString(), descHash };
}

function main() {
    const jsonPath = process.argv[2] || path.join(__dirname, "calldata.json");
    const entries = JSON.parse(fs.readFileSync(jsonPath, "utf8"));
    // Canonical description (must match the Forge builder's DESCRIPTION constant byte-for-byte).
    const description = fs.readFileSync(path.join(__dirname, "description.txt"), "utf8").replace(/\n$/, "");
    const targets = entries.map((e) => e.target);
    const values = entries.map((e) => e.value);
    const calldatas = entries.map((e) => e.calldata);
    const { id: proposalId, descHash } = computeProposalId(targets, values, calldatas, description);
    const groups = [
        { name: "A — Migrate Timelock roles (old → new GovernorOLAS)", idx: [0, 1, 2, 3, 4, 5, 6, 7] },
        { name: "B — Configure bridge mediators on new GuardCM (Mode excluded)", idx: [8, 9, 10, 11] },
        { name: "C — CM target-selector allowlist on new GuardCM (16 entries)", idx: [12] },
        { name: "D — Swap CM guard via Timelock Safe-module", idx: [13] },
        { name: "E — Set new Celo BalanceTrackers (bridged, OP-stack)", idx: [14] },
        { name: "F — Upgrade Tokenomics implementation", idx: [15] },
    ];
    // propose() copy-paste inputs (Boardroom / Etherscan format)
    const jsonArr = (a) => "[" + a.map((x) => `"${x}"`).join(",") + "]";
    const proposeInputs =
        "<h2>propose() inputs — copy into GovernorOLAS</h2>" +
        `<div class="entry"><div class="pi"><div class="pk">Targets</div><pre class="cp">${esc(jsonArr(targets))}</pre>` +
        `<div class="pk">Values</div><pre class="cp">[${values.join(",")}]</pre>` +
        `<div class="pk">Calldatas</div><pre class="cp">${esc(jsonArr(calldatas))}</pre>` +
        `<div class="pk">proposalDescription</div><pre class="cp">${esc(description)}</pre>` +
        `<div class="pk">proposalId (pre-computed)</div><pre class="cp">${esc(proposalId)}</pre>` +
        `<div class="pk">descriptionHash</div><pre class="cp">${esc(descHash)}</pre></div></div>`;

    let body = proposeInputs;
    for (const g of groups) {
        body += `<h2>${esc(g.name)}</h2>`;
        for (const i of g.idx) {
            const e = entries[i];
            body += `<div class="entry"><div class="ehead"><span class="ix">[${i}]</span> target = ${addrSpan(e.target)} &nbsp; value = <span class="val">${esc(e.value)}</span></div>` +
                decodeEntry(e) +
                `<details class="raw"><summary>raw calldata</summary><pre>${esc(e.calldata)}</pre></details></div>`;
        }
    }
    const html = `<!doctype html><html><head><meta charset="utf-8"><title>Proposal 11 - Olas Governance & GuardCM activation</title>
<style>
:root{--bg:#0f1115;--fg:#e6e6e6;--mut:#8a93a2;--sel:#c792ea;--addr:#82aaff;--val:#c3e88d;--role:#89ddff;--box:#161922;--bd:#2a2f3a;--ok:#7fd1a0;--bad:#ff8b8b;--cp:#ffd479}
body{background:var(--bg);color:var(--fg);font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;margin:0;padding:24px}
h1{font-size:18px} h2{font-size:14px;margin:26px 0 8px;color:#fff;border-bottom:1px solid var(--bd);padding-bottom:4px}
.lead{color:var(--mut);max-width:80ch}
.entry{border:1px solid var(--bd);border-radius:8px;margin:10px 0;padding:10px;background:#11141b}
.ehead{margin-bottom:6px}
.ix{color:var(--mut);margin-right:6px}
details.call{border-left:2px solid var(--bd);margin:4px 0 4px 6px;padding-left:8px}
details.call>summary{cursor:pointer;color:var(--fg)}
.body{padding:4px 0 4px 10px}
.row{padding:1px 0} .key{color:var(--mut)}
.sel{color:var(--sel)} .addr{color:var(--addr)} .val{color:var(--val)} .role{color:var(--role)}
.note{color:var(--mut);font-style:italic}
.ok{color:var(--ok)} .bad{color:var(--bad)}
table.al{border-collapse:collapse;margin:6px 0;font-size:12px}
table.al th,table.al td{border:1px solid var(--bd);padding:3px 7px;text-align:left;white-space:nowrap}
table.al th{color:#fff;background:#1b1f29} td.num{color:var(--mut)} td.addr{color:var(--addr)} td.sel{color:var(--sel)}
details.raw{margin-top:6px} details.raw>summary{color:var(--mut);cursor:pointer}
details.raw pre{white-space:pre-wrap;word-break:break-all;color:var(--mut);background:#0b0d12;border:1px solid var(--bd);border-radius:6px;padding:8px}
.pk{color:#fff;margin:8px 0 2px;font-weight:bold} pre.cp{white-space:pre-wrap;word-break:break-all;background:#0b0d12;border:1px solid var(--bd);border-radius:6px;padding:8px;color:var(--cp)}
.pid{color:var(--ok);font-weight:bold}
a{color:var(--addr)}
</style></head><body>
<h1>Proposal 11 — Olas Governance &amp; GuardCM activation (annotated)</h1>
<p class="lead">Submit via <b>propose()</b> on the OLD GovernorOLAS (0x8E84B5…3b401). 16 entries, all values 0.
Decoded directly from the Forge builder's verified calldata. Hover any address/selector for its label; expand nested calls.</p>
<p class="lead">Pre-computed <span class="pid">proposalId = ${esc(proposalId)}</span></p>
${body}
<h2>proposalId</h2>
<div class="entry"><pre class="cp pid">${esc(proposalId)}</pre>
<div class="note">= uint256(keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description)))))</div></div>
</body></html>`;
    const outPath = path.join(__dirname, "proposal_11.html");
    fs.writeFileSync(outPath, html);
    console.log("Wrote", outPath, "(" + entries.length + " entries)");
    console.log("proposalId:", proposalId);
}

main();
