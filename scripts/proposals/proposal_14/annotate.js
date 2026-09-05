/*global process, __dirname*/
// Generates a self-contained, color-coded, collapsible HTML breakdown of proposal 14 (L2 withheld-amount sync).
// It DECODES the authoritative calldata produced by the Forge builder (calldata.json, parsed from the builder's
// run() output), so the artifact cannot drift from what is voted. Groups are auto-derived from the selectors.
//
// Usage (from repo root):
//   forge script scripts/proposals/<folder>/<Builder>.s.sol:<Builder> > /tmp/run.txt
//   # parse the [--- index N ---/target/value/calldata] blocks into <folder>/calldata.json, then:
//   node scripts/proposals/<folder>/annotate.js "Proposal 12 — un-nominate legacy staking contracts"
// Writes <folder>.html next to this script (name derived from the folder).

const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

const abi = ethers.utils.defaultAbiCoder;
const lc = (a) => (a || "").toLowerCase();

const ADDR = {
    // proposal 13 labels. NOTE: 0x9338b515... is BOTH the Polygon FxGovernorTunnel and the Mode
    // mediator, and 0x87c511c8... is BOTH the Optimism L2 messenger and the Mode StakingVerifier.
    // The renderer picks the chain from the L1 entrypoint (FxRoot -> 137, Mode L1CDM -> 34443),
    // never from the L2 address, so these collisions do not mislabel.
    "0xdcafcccc7ba0b7185a472d9d068fde0af4313fb5": "ProcessBridgedDataOptimism (OP-stack verifier)",
    "0x88de734655184a09b70700ae4f72364d1ad23728": "Superseded V1 staking implementation (Mode)",
    "0xa749f605d93b3efcc207c54270d83c6e8fa70ff8": "PolySafeCreatorWithRecoveryModule (Polygon)",
    // proposal 12 nominee labels (legacy staking contracts being un-nominated)
    "0xab10188207ea030555f53c8a84339a92f473aa5e": "Pearl Beta Mech Marketplace (Gnosis)",
    "0x8d7be092d154b01d404f1accfa22cef98c613b5d": "Pearl Beta Mech Marketplace II (Gnosis)",
    "0x9d00a0551f20979080d3762005c9b74d7aa77b85": "Pearl Beta Mech Marketplace III (Gnosis)",
    "0xe2f80659db1069f3b6a08af1a62064190c119543": "Pearl Beta Mech Marketplace IV (Gnosis)",
    "0x536d04dbd9a2310152a0d2d8d18dadfca8bb26b0": "Pearl Beta Mech Marketplace V (Gnosis)",
    "0xac3ed39d18d9c951bd2e7f0024114849c0a25295": "Pearl Beta Mech Marketplace VI (Gnosis)",
    "0xb2303f9913f11131a74f4b05099ced2043cc72c4": "Pearl Beta Mech Marketplace VII (Gnosis)",
    "0x12bdd401ac300482f4017c64c6c930ee40424c08": "Pearl Beta Mech Marketplace VIII (Gnosis)",
    "0x8887c2852986e7cbac99b6065ffe53074a6bcc26": "Polymarket Alpha - III (Polygon)",
    "0x9f1936f6afb5eaaa2220032cf5e265f2cc9511cc": "Polymarket Beta - I (Polygon)",
    "0x22d58680f643333f93205b956a4aa1dc203a16ad": "Polymarket Beta - II (Polygon)",
    "0xbca056952d2a7a8dd4a002079219807cfdf9fd29": "Optimus Alpha II (Optimism)",
    "0x0f69f35652b1acdbd769049334f1ac580927e139": "Optimus Alpha III (Optimism)",
    "0x6891cf116f9a3bdbd1e89413118ef81f69d298c3": "Optimus Alpha IV (Optimism)",
    "0xfa0ca3935758cb81d35a8f1395b9eb5a596ce301": "Pett.AI Agent Staking Contract (Base)",
    "0x00d544c10bdc0e9b0a71ceaf52c1342bb8f21c1d": "Pett.AI Agent Staking Contract 2 (Base)",
    "0x2585e63df7bd9de8e058884d496658a030b5c6ce": "Agents.fun 1 (Base)",
    "0x26fa75ef9ccaa60e58260226a71e9d07564c01bf": "Agents.fun 2 (Base)",
    "0x4d4233ebf0473ca8f34d105a6256a2389176f0ce": "Agents.fun 3 (Base)",
    "0x0dfafbf570e9e813507aae18aa08dfba0abc5139": "unused staking contract, invalid metadata (Base)",
    "0x3c1ff68f5aa342d296d4dee4bb1cacca912d95fe": "Timelock (Ethereum) / ServiceRegistryL2 (Base, Mode)",
    "0x060d0cbddfb0498d610e2ef55c01516b5b1251e6": "GovernorOLAS (live)",
    "0x95418b46d5566d3d1ea62c12aea91227e566c5c1": "VoteWeighting",
    "0xc0b146d61e2a2c17e024477e01978d1fcf598c6b": "GuardCM",
    // L1 bridge entry points
    "0x4c36d2919e407f0cc2ee3c993ccf8ac26d9ce64e": "Gnosis AMB (L1)",
    "0xfe5e5d361b2ad62c541bab87c45a0b9b018389a2": "Polygon FxRoot (L1)",
    "0x4dbd4fc535ac27206064b68ffcf827b0a60bab3f": "Arbitrum Inbox (L1)",
    "0x25ace71c97b33cc4729cf772ae268934f7ab5fa1": "Optimism L1CrossDomainMessenger",
    "0x866e82a600a1414e583f7f13623f1ac5d58b0afa": "Base L1CrossDomainMessenger",
    "0x1ac1181fc4e4f877963680587aeaa2c90d7ebb95": "Celo L1CrossDomainMessenger",
    "0x95bdca6c8edeb69c98bd5bd17660bacef1298a6f": "Mode L1CrossDomainMessenger",
    // L2 mediators / messengers
    "0x15bd56669f57192a97df41a2aa8f4403e9491776": "HomeMediator (Gnosis L2)",
    "0x9338b5153ae39bb89f50468e608ed9d764b755fd": "FxGovernorTunnel (Polygon) / OptimismMessenger (Mode) / ServiceRegistryL2 (Gnosis)",
    "0x4d30f68f5aa342d296d4dee4bb1cacca912da70f": "Aliased Timelock / BridgeMediator (Arbitrum L2)",
    "0x87c511c8ae3faf0063b3f3cf9c6ab96c4aa5c60c": "OptimismMessenger (Optimism L2)",
    "0xe49cb081e8d96920c38aa7ab90cb0294ab4bc8ea": "OptimismMessenger (Base L2)",
    "0xc14e191a64a7fb0e5790a8a0b9a58683dffce04d": "OptimismMessenger (Celo L2)",
    // ServiceRegistry / ServiceRegistryL2 (de-whitelist targets)
    "0x48b6af7b12c71f09e2fc8af4855de4ff54e775ca": "ServiceRegistry (Ethereum)",
    "0xe3607b00e75f6405248323a9417ff6b39b244b50": "ServiceRegistryL2 (Polygon, Arbitrum, Celo)",
    "0x3d77596beb0f130a4415df3d2d8232b3d3d31e44": "ServiceRegistryL2 (Optimism)",
    // same-address multisig implementations (being disabled)
    "0xfa517d01daa100cb1932fa4345f68874f7e7ef46": "GnosisSafeSameAddressMultisig (Ethereum)",
    "0x6e7f594f680f7abad18b7a63de50f0fee47dfd06": "GnosisSafeSameAddressMultisig (Gnosis)",
    "0xd8bcc126ff31d2582018715d5291a508530587b0": "GnosisSafeSameAddressMultisig (Polygon)",
    "0xbcb1bac84b5bcab350c89c50adc9064ed15a4485": "PolySafeSameAddressMultisig (Polygon)",
    "0xbb7e1d6cb6f243d6bde81ce92a9f2aff7fbe7eac": "GnosisSafeSameAddressMultisig (Arbitrum, Celo)",
    "0xb09ccf0dbf0c178806aaee28956c74bd66d21f73": "GnosisSafeSameAddressMultisig (Optimism)",
    "0xfbbec0c8b13b38a9ac0499694a69a10204c5e2ab": "GnosisSafeSameAddressMultisig (Base, Mode)",
    // GuardCM Phase 1 allowlist targets
    "0x5650300fcbab43a0d7d02f8cb5d0f039402593f0": "Dispenser",
    "0x94a1892d91c05d0c61c3f49f42205d2285b914c9": "ServiceManagerProxy (Ethereum)",
    "0x9ec9156def5c613b2a7d4c46c383f9b58dfcd6fe": "RegistriesManager (Ethereum)",
    "0xa5c7fbccff28441b7d250412b0fb87aa1c8b14ad": "ServiceManagerProxy (Optimism)",
    "0xaea9ef993d8a1a164397642648df43f053d43d85": "OptimismTargetDispenserL2 (Optimism)",
    "0x068a4f0946cf8c7f9c1b58a3b5243ac8843bf473": "ServiceManagerProxy (Gnosis)",
    "0x5b6c538c7b2e0b44fa8a3b7a0532ef797b07d0e9": "GnosisTargetDispenserL2 (Gnosis)",
    "0xe3e5df46060370af5fd37b2aa11e7dac3ccb4bd0": "ServiceManagerProxy (Polygon)",
    "0x17d96ba4532fe91809326092fe4d5606a7b7a0d8": "PolygonTargetDispenserL2 (Polygon)",
    "0x1262136cac6a06a782dc94eb3a3df0b4d09ff6a6": "ServiceManagerProxy (Base)",
    "0x9ec97be9ff55ff11606ce7c589956f7bf3d0b241": "BaseTargetDispenserL2 (Base)",
    "0xcddd9d9abab36ffa882530d69c73fee5d4001c2d": "ServiceManagerProxy (Mode)",
    "0xeb5638eefe289691ece01943f768edbf96258a80": "ModeTargetDispenserL2 (Mode)",
    "0x34c895f302d0b5cf52ec0edd3945321eb0f83dd5": "ServiceRegistryTokenUtility (Mode)",
    "0xd421f433e36465b3e558b1121f584ac09fc33df8": "ServiceManagerProxy (Arbitrum)",
    "0x5953f21495bd9af1d78e87bb42accaa55c1e896c": "ArbitrumTargetDispenserL2 (Arbitrum)",
    "0x84b4da67b37b1ea1dea9c7044042c1d2297b80a0": "ServiceManagerProxy (Celo)",
    "0x4891f5894634dcd6d11644fe8e56756ef2681582": "CeloTargetDispenserL2 (Celo)",
};
const SELSIG = {
    "0x82694b1d": "changeMultisigPermission(address,bool)",
    "0x1602c55c": "setBridgeMediatorL1BridgeParams(address[],address[],uint256[],address[])",
    "0x0bea55ed": "setImplementationsStatuses(address[],bool[],bool)",
    "0xc54dd0d4": "removeNominee(bytes32,uint256)",
    "0x5d78d469": "setTargetSelectorChainIds(address[],bytes4[],uint256[],bool[])",
    "0x3dbb202b": "sendMessage(address,bytes,uint32)",
    "0xd3042d2b": "processMessageFromSource(bytes)",
    "0xcd9e30d9": "processMessageFromForeign(bytes)",
    "0xdc8601b3": "requireToPassMessage(address,bytes,uint256)",
    "0xb4720477": "sendMessageToChild(address,bytes)",
    "0x679b6ded": "createRetryableTicket(address,uint256,uint256,address,address,uint256,uint256,bytes)",
    "0x7424ddc8": "syncWithheldAmount(bytes)",
    "0x8456cb59": "pause()",
    "0x63096509": "setPauseState(uint8)",
    "0x9890220b": "drain()",
    "0xece53132": "drain(address)",
};
const CHAIN = { 1: "Ethereum", 100: "Gnosis", 137: "Polygon", 42161: "Arbitrum", 10: "Optimism", 8453: "Base", 42220: "Celo", 34443: "Mode" };
// L1 cross-domain messenger -> destination chain. This is the authoritative direction: an L1 entrypoint
// is unique per chain, while an L2 receiver address may be reused across chains.
const L1CDM2CHAIN = {
    "0x25ace71c97b33cc4729cf772ae268934f7ab5fa1": 10,     // Optimism
    "0x866e82a600a1414e583f7f13623f1ac5d58b0afa": 8453,   // Base
    "0x1ac1181fc4e4f877963680587aeaa2c90d7ebb95": 42220,  // Celo
    "0x95bdca6c8edeb69c98bd5bd17660bacef1298a6f": 34443,  // Mode
};

const EXPLORER = {
    1: "https://etherscan.io/address/",
    100: "https://gnosisscan.io/address/",
    137: "https://polygonscan.com/address/",
    42161: "https://arbiscan.io/address/",
    10: "https://optimistic.etherscan.io/address/",
    8453: "https://basescan.org/address/",
    42220: "https://celoscan.io/address/",
    34443: "https://explorer.mode.network/address/",
};

const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
// Chain-keyed overrides, consulted BEFORE the flat ADDR map. Several addresses in this proposal are
// different contracts on different chains through deployer-nonce reuse, and the flat map cannot express
// that — 0x87c511c8… is Optimism's L2 messenger AND Mode's StakingVerifier, and 0x9338b515… is Polygon's
// FxGovernorTunnel AND Mode's mediator. Without this the annotated HTML labels them with whichever entry
// happens to be in ADDR, which is the exact collision this proposal warns reviewers about.
const ADDR_BY_CHAIN = {
    "34443:0x87c511c8ae3faf0063b3f3cf9c6ab96c4aa5c60c": "StakingVerifier (Mode)",
    "34443:0x9338b5153ae39bb89f50468e608ed9d764b755fd": "OptimismMessenger mediator (Mode)",
    "34443:0x88de734655184a09b70700ae4f72364d1ad23728": "Superseded V1 staking implementation (Mode)",
    "137:0x9338b5153ae39bb89f50468e608ed9d764b755fd": "FxGovernorTunnel (Polygon)",
    "137:0xe3607b00e75f6405248323a9417ff6b39b244b50": "ServiceRegistryL2 (Polygon)",
    "137:0xa749f605d93b3efcc207c54270d83c6e8fa70ff8": "PolySafeCreatorWithRecoveryModule (Polygon)",
    // Fourth collision: the same 20 bytes are the L1 Timelock on Ethereum and ServiceRegistryL2 on Mode.
    // Without this entry a Mode drain() annotation would print "Timelock".
    "34443:0x3c1ff68f5aa342d296d4dee4bb1cacca912d95fe": "ServiceRegistryL2 (Mode)",
    "1:0x3c1ff68f5aa342d296d4dee4bb1cacca912d95fe": "Timelock (Ethereum)",
};

const addrSpan = (a, chainId = 1) => {
    const cid = Number(chainId);
    const addr = ethers.utils.getAddress(a);
    const name = ADDR_BY_CHAIN[cid + ":" + lc(a)] || ADDR[lc(a)];
    const label = (name ? name + " · " : "") + (CHAIN[cid] || ("chain " + cid));
    const url = (EXPLORER[cid] || EXPLORER[1]) + addr + "#code";
    return `<a class="addr" href="${url}" target="_blank" rel="noopener" title="${esc(label)}">${esc(addr)}</a>` +
        ` <span class="note">// ${esc(label)}</span>`;
};
const selSpan = (sel) => {
    const sig = SELSIG[lc(sel)] || "unknown";
    return `<span class="sel" title="${esc(sig)}">${esc(sel)}</span> <span class="note">// ${esc(sig)}</span>`;
};
const valSpan = (v, note) => `<span class="val">${esc(v)}</span>` + (note ? ` <span class="note">// ${esc(note)}</span>` : "");
const boolSpan = (b) => b ? "<span class=\"ok\">true (enable)</span>" : "<span class=\"bad\">false (disable)</span>";
function row(name, html) { return `<div class="row"><span class="key">${esc(name)}</span> = ${html}</div>`; }
function callBox(title, inner, open = true) {
    return `<details class="call"${open ? " open" : ""}><summary>${title}</summary><div class="body">${inner}</div></details>`;
}
const addrFromBytes32 = (b32) => ethers.utils.getAddress("0x" + b32.slice(-40));

function renderPayload(payload, chainId) {
    const sel = payload.slice(0, 10);
    if (sel === "0x0bea55ed") {
        const [impls, statuses, setCheck] = abi.decode(["address[]", "bool[]", "bool"], "0x" + payload.slice(10));
        let rows = "";
        for (let i = 0; i < impls.length; i++) {
            rows += row(`implementations[${i}]`, addrSpan(ethers.utils.getAddress(impls[i]), chainId)) +
                row(`statuses[${i}]`, boolSpan(statuses[i]));
        }
        // setCheck is assigned UNCONDITIONALLY by the contract: false would disable the whole allowlist.
        rows += row("setCheck", setCheck
            ? "<span class=\"ok\">true</span> <span class=\"note\">// allowlist stays ENFORCED</span>"
            : "<span class=\"bad\">false</span> <span class=\"note\">// WARNING: disables the allowlist entirely</span>");
        return callBox(selSpan(sel), rows, true);
    }
    if (sel === "0x82694b1d") {
        const [ms, perm] = abi.decode(["address", "bool"], "0x" + payload.slice(10));
        return callBox(selSpan(sel), row("multisig", addrSpan(ms, chainId)) + row("permission", boolSpan(perm)), true);
    }
    if (sel === "0x7424ddc8") {
        const [bridgePayload] = abi.decode(["bytes"], "0x" + payload.slice(10));
        // The dispenser clamps this to [300k, 2M] and ignores anything that is not 32 bytes; Polygon
        // and Arbitrum ignore it entirely. It is the gas for the RETURN message, L2 -> L1.
        const note = bridgePayload === "0x"
            ? "empty — this bridge ignores the payload"
            : ethers.BigNumber.from(bridgePayload).toString() + " gas for the return message (clamped to 300k..2M)";
        return callBox(selSpan(sel),
            row("bridgePayload", `<span class="val">${esc(bridgePayload)}</span> <span class="note">// ${esc(note)}</span>`) +
            "<div class=\"row note\">reads the dispenser's own withheldAmount at execution time — no amount is a parameter here</div>",
            true);
    }
    return callBox(selSpan(sel), `<div class="row note">payload: ${esc(payload)}</div>`, true);
}

// Olas bridge packing: target(20) | value(uint96,12) | payloadLength(uint32,4) | payload (concatenated tuples).
function decodePacked(packed, chainId) {
    const pk = packed.slice(2);
    let out = "", n = 0;
    for (let i = 0; i < pk.length;) {
        const target = ethers.utils.getAddress("0x" + pk.slice(i, i + 40)); i += 40;
        const value = ethers.BigNumber.from("0x" + pk.slice(i, i + 24)).toString(); i += 24;
        const plen = parseInt(pk.slice(i, i + 8), 16); i += 8;
        const payload = "0x" + pk.slice(i, i + plen * 2); i += plen * 2;
        out += callBox(`<span class="key">tuple[${n}]</span> <span class="note">// target(20)|value(12)|len(4)|payload</span>`,
            row("target", addrSpan(target, chainId)) + row("value", valSpan(value)) +
            row("payloadLength", valSpan(plen + " bytes")) +
            "<div class=\"row\"><span class=\"key\">payload</span> &darr;</div>" + renderPayload(payload, chainId), true);
        n++;
    }
    return out;
}

// Group by what the entry DOES and where it lands, resolving the chain from the L1 entrypoint. Keying an
// OP-stack entry off its selector would be wrong: 0x3dbb202b is sendMessage on ANY OP-stack L1 messenger,
// so an Optimism, Base or Celo leg would be filed under whichever chain-named heading was hardcoded.
const CHAIN_GROUP = {10: "optimism", 8453: "base", 42220: "celo", 34443: "mode"};
function category(e) {
    const sel = e.calldata.slice(0, 10);
    if (sel === "0xb4720477") return "polygon";
    if (sel === "0xdc8601b3") return "gnosis";
    if (sel === "0x679b6ded") return "arbitrum";
    if (sel === "0x3dbb202b") {
        const cid = L1CDM2CHAIN[lc(e.target)];
        return CHAIN_GROUP[cid] || "other";
    }
    return "other";
}
const GROUP_ORDER = [
    ["polygon", "Polygon: sync withheld amount (bridged via FxRoot)"],
    ["gnosis", "Gnosis: sync withheld amount (bridged via the AMB)"],
    ["optimism", "Optimism: sync withheld amount (bridged)"],
    ["base", "Base: sync withheld amount (bridged)"],
    ["celo", "Celo: sync withheld amount (bridged)"],
    ["mode", "Mode: sync withheld amount (bridged)"],
    ["arbitrum", "Arbitrum: sync withheld amount (retryable ticket, executes as the aliased Timelock)"],
    ["other", "Other"],
];

function decodeEntry(e) {
    const sel = e.calldata.slice(0, 10);
    const args = "0x" + e.calldata.slice(10);
    const head = selSpan(sel);

    if (sel === "0x82694b1d") {
        const [ms, perm] = abi.decode(["address", "bool"], args);
        return callBox(head, row("multisig", addrSpan(ms, 1)) + row("permission", boolSpan(perm)));
    }
    if (sel === "0xc54dd0d4") {
        const [acct, cid] = abi.decode(["bytes32", "uint256"], args);
        const c = Number(cid);
        return callBox(head, row("account (bytes32)", `<span class="val">${esc(acct)}</span>`) +
            row("&rarr; address", addrSpan(addrFromBytes32(acct), c)) +
            row("chainId", valSpan(cid.toString(), CHAIN[c] || "")));
    }
    if (sel === "0x5d78d469") {
        const [t, s, c, st] = abi.decode(["address[]", "bytes4[]", "uint256[]", "bool[]"], args);
        let rows = "";
        for (let i = 0; i < t.length; i++) {
            const cid = Number(c[i]);
            const addr = ethers.utils.getAddress(t[i]);
            const url = (EXPLORER[cid] || EXPLORER[1]) + addr + "#code";
            rows += `<tr><td class="num">${i}</td><td>${esc(ADDR[lc(addr)] || "?")}</td>` +
                `<td><a class="addr" href="${url}" target="_blank" rel="noopener">${esc(addr)}</a></td>` +
                `<td class="sel">${esc(s[i])}</td><td>${esc(SELSIG[lc(s[i])] || "")}</td>` +
                `<td>${c[i]} <span class="note">${esc(CHAIN[cid] || "")}</span></td>` +
                `<td>${st[i] ? "<span class=\"ok\">enable</span>" : "<span class=\"bad\">disable</span>"}</td></tr>`;
        }
        return callBox(head, `<table class="al"><thead><tr><th>#</th><th>target</th><th>address</th><th>selector</th><th>function</th><th>chain</th><th>status</th></tr></thead><tbody>${rows}</tbody></table>`);
    }
    if (sel === "0x1602c55c") {
        const [l1s, vs, cids, l2s] = abi.decode(["address[]", "address[]", "uint256[]", "address[]"], args);
        let rows = "";
        for (let i = 0; i < l1s.length; i++) {
            const cid = Number(cids[i]);
            rows += `<tr><td class="num">${i}</td>` +
                `<td>${esc(ADDR[lc(l1s[i])] || "?")}</td>` +
                `<td>${addrSpan(ethers.utils.getAddress(l1s[i]), 1)}</td>` +
                `<td>${addrSpan(ethers.utils.getAddress(vs[i]), 1)}</td>` +
                `<td>${cids[i]} <span class="note">${esc(CHAIN[cid] || "")}</span></td>` +
                `<td>${addrSpan(ethers.utils.getAddress(l2s[i]), cid)}</td></tr>`;
        }
        return callBox(head, "<table class=\"al\"><thead><tr><th>#</th><th>L1 mediator</th><th>address</th>" +
            `<th>verifierL2</th><th>chainId</th><th>bridgeMediatorL2</th></tr></thead><tbody>${rows}</tbody></table>`);
    }
    if (sel === "0x3dbb202b") {
        const [target, message, minGas] = abi.decode(["address", "bytes", "uint32"], args);
        // Resolve the destination chain from the L1 ENTRYPOINT (the proposal target), never from the L2
        // receiver. The receiver address is ambiguous across chains — 0x9338b515… is both Polygon's
        // FxGovernorTunnel and Mode's mediator — whereas the L1 messenger is unique per chain.
        const cid = L1CDM2CHAIN[lc(e.target)];
        if (!cid) {
            throw new Error("unknown L1 cross-domain messenger " + e.target + " — add it to L1CDM2CHAIN");
        }
        const pSel = message.slice(0, 10);
        const [packed] = abi.decode(["bytes"], "0x" + message.slice(10));
        const procBox = callBox(selSpan(pSel), decodePacked(packed, cid), true);
        return callBox(head, row("_target (L2 receiver)", addrSpan(target, cid)) + row("_minGasLimit", valSpan(minGas.toString())) +
            "<div class=\"row\"><span class=\"key\">_message</span> &darr;</div>" + procBox);
    }
    if (sel === "0xdc8601b3") {
        const [l2med, data, gas] = abi.decode(["address", "bytes", "uint256"], args);
        const pSel = data.slice(0, 10);
        const [packed] = abi.decode(["bytes"], "0x" + data.slice(10));
        const procBox = callBox(selSpan(pSel), decodePacked(packed, 100), true);
        return callBox(head, row("_contract (HomeMediator, Gnosis L2)", addrSpan(l2med, 100)) + row("_gas", valSpan(gas.toString())) +
            "<div class=\"row\"><span class=\"key\">_data</span> &darr;</div>" + procBox);
    }
    if (sel === "0xb4720477") {
        const [tunnel, packed] = abi.decode(["address", "bytes"], args);
        return callBox(head, row("_receiver (FxGovernorTunnel, Polygon L2)", addrSpan(tunnel, 137)) +
            "<div class=\"row\"><span class=\"key\">_data (packed)</span> &darr;</div>" + decodePacked(packed, 137));
    }
    if (sel === "0x679b6ded") {
        const [to, l2v, maxSub, exRef, cvRef, gasLim, maxFee, data] = abi.decode(
            ["address", "uint256", "uint256", "address", "address", "uint256", "uint256", "bytes"], args);
        return callBox(head,
            row("to (L2 target)", addrSpan(to, 42161)) + row("l2CallValue", valSpan(l2v.toString())) +
            row("maxSubmissionCost", valSpan(maxSub.toString(), "wei")) +
            row("excessFeeRefundAddress", addrSpan(exRef, 42161)) + row("callValueRefundAddress", addrSpan(cvRef, 1)) +
            row("gasLimit", valSpan(gasLim.toString())) + row("maxFeePerGas", valSpan(maxFee.toString(), "wei")) +
            "<div class=\"row\"><span class=\"key\">data</span> &darr;</div>" + renderPayload(data, 42161));
    }
    return callBox(head, "<div class=\"row note\">unrecognized selector</div>");
}

function computeProposalId(targets, values, calldatas, description) {
    const descHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(description));
    const encoded = abi.encode(["address[]", "uint256[]", "bytes[]", "bytes32"], [targets, values, calldatas, descHash]);
    return { id: ethers.BigNumber.from(ethers.utils.keccak256(encoded)).toString(), descHash };
}

function main() {
    const title = process.argv[2] || "Proposal (annotated)";
    const entries = JSON.parse(fs.readFileSync(path.join(__dirname, "calldata.json"), "utf8"));
    const description = fs.readFileSync(path.join(__dirname, "description.txt"), "utf8").replace(/\n$/, "");
    const targets = entries.map((e) => e.target);
    const values = entries.map((e) => e.value);
    const calldatas = entries.map((e) => e.calldata);
    const { id: proposalId, descHash } = computeProposalId(targets, values, calldatas, description);

    // auto-group by selector category
    const byCat = {};
    entries.forEach((e, i) => { (byCat[category(e)] ||= []).push(i); });
    const nonZero = entries.map((e, i) => (e.value !== "0" ? i : -1)).filter((i) => i >= 0);

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
    for (const [cat, name] of GROUP_ORDER) {
        const idx = byCat[cat];
        if (!idx || !idx.length) continue;
        body += `<h2>${esc(name)} (${idx.length})</h2>`;
        for (const i of idx) {
            const e = entries[i];
            body += `<div class="entry"><div class="ehead"><span class="ix">[${i}]</span> target = ${addrSpan(e.target)} &nbsp; value = <span class="val">${esc(e.value)}</span></div>` +
                decodeEntry(e) +
                `<details class="raw"><summary>raw calldata</summary><pre>${esc(e.calldata)}</pre></details></div>`;
        }
    }
    // Derived from the calldata, never asserted from memory. This branch had never executed before
    // proposal 14 — every earlier proposal was all-zero-value — and the sentence it used to carry
    // (a "deposit x10 buffer" "supplied by the executor") was true of neither this proposal nor any
    // other. Anything stated here about an entry's value must come out of that entry's own bytes.
    const describeValue = (i) => {
        const e = entries[i];
        const sel = e.calldata.slice(0, 10);
        if (sel !== "0x679b6ded") {
            return `entry [${i}] carries ${esc(e.value)} wei`;
        }
        const [, , maxSub, , , gasLim, maxFee] = abi.decode(
            ["address", "uint256", "uint256", "address", "address", "uint256", "uint256", "bytes"],
            "0x" + e.calldata.slice(10));
        // The Inbox recomputes the submission fee AT EXECUTION as (1400 + 6*dataLength)*block.basefee,
        // so what maxSubmissionCost really states is the base fee this entry tolerates.
        const dataLen = ethers.utils.hexDataLength(
            abi.decode(["address", "uint256", "uint256", "address", "address", "uint256", "uint256", "bytes"],
                "0x" + e.calldata.slice(10))[7]);
        const units = ethers.BigNumber.from(1400 + 6 * dataLen);
        const ceilingGwei = ethers.utils.formatUnits(maxSub.div(units), "gwei");
        const gasPart = gasLim.mul(maxFee);
        return `entry [${i}] (Arbitrum retryable) carries ${esc(e.value)} wei = maxSubmissionCost ` +
            `${maxSub.toString()} + gasLimit ${gasLim.toString()} &times; maxFeePerGas ${maxFee.toString()} ` +
            `(${gasPart.toString()}). The Inbox recomputes the submission fee at execution as ` +
            "(1400 + 6&times;dataLength) &times; block.basefee, so this prices an L1 base fee up to " +
            `<b>${esc(ceilingGwei)} gwei</b>; above that the entry reverts, and with it the whole batch. ` +
            "The Timelock funds it from its own balance — no value is attached to execute().";
    };
    const valNote = nonZero.length
        ? `All values are 0 EXCEPT ${nonZero.map(describeValue).join("; ")}`
        : "Every entry has value 0.";
    const html = `<!doctype html><html><head><meta charset="utf-8"><title>${esc(title)}</title>
<style>
:root{--bg:#0f1115;--fg:#e6e6e6;--mut:#8a93a2;--sel:#c792ea;--addr:#82aaff;--val:#c3e88d;--role:#89ddff;--box:#161922;--bd:#2a2f3a;--ok:#7fd1a0;--bad:#ff8b8b;--cp:#8a93a2}
body{background:var(--bg);color:var(--fg);font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;margin:0;padding:24px}
h1{font-size:18px} h2{font-size:14px;margin:26px 0 8px;color:#fff;border-bottom:1px solid var(--bd);padding-bottom:4px}
.lead{color:var(--mut);max-width:90ch}
.entry{border:1px solid var(--bd);border-radius:8px;margin:10px 0;padding:10px;background:#11141b}
.ehead{margin-bottom:6px} .ix{color:var(--mut);margin-right:6px}
details.call{border-left:2px solid var(--bd);margin:4px 0 4px 6px;padding-left:8px}
details.call>summary{cursor:pointer;color:var(--fg)} .body{padding:4px 0 4px 10px}
.row{padding:1px 0} .key{color:var(--mut)}
.sel{color:var(--sel)} .addr{color:var(--addr)} .val{color:var(--val)} .role{color:var(--role)}
.note{color:var(--mut);font-style:italic} .ok{color:var(--ok)} .bad{color:var(--bad)}
table.al{border-collapse:collapse;margin:6px 0;font-size:12px}
table.al th,table.al td{border:1px solid var(--bd);padding:3px 7px;text-align:left;white-space:nowrap}
table.al th{color:#fff;background:#1b1f29} td.num{color:var(--mut)} td.sel{color:var(--sel)}
details.raw{margin-top:6px} details.raw>summary{color:var(--mut);cursor:pointer}
details.raw pre{white-space:pre-wrap;word-break:break-all;color:var(--mut);background:#0b0d12;border:1px solid var(--bd);border-radius:6px;padding:8px}
.pk{color:#fff;margin:8px 0 2px;font-weight:bold} pre.cp{white-space:pre-wrap;word-break:break-all;background:#0b0d12;border:1px solid var(--bd);border-radius:6px;padding:8px;color:var(--cp)}
.pid{color:var(--ok);font-weight:bold} a{color:var(--addr)}
</style></head><body>
<h1>${esc(title)} (annotated)</h1>
<p class="lead">Submit via <b>propose()</b> on the live GovernorOLAS (0x060D0C&hellip;251E6), which holds the Timelock
roles. <b>${entries.length} entries</b>; every call is executed by the Timelock. ${valNote} Decoded directly from
the Forge builder's verified calldata — hover any address/selector for its label; expand nested calls.</p>
<p class="lead">Pre-computed <span class="pid">proposalId = ${esc(proposalId)}</span></p>
${body}
<h2>proposalId</h2>
<div class="entry"><pre class="cp pid">${esc(proposalId)}</pre>
<div class="note">= uint256(keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description)))))</div></div>
</body></html>`;
    const outPath = path.join(__dirname, path.basename(__dirname) + ".html");
    fs.writeFileSync(outPath, html);
    console.log("Wrote", outPath, "(" + entries.length + " entries)");
    console.log("proposalId:", proposalId);
}

main();
