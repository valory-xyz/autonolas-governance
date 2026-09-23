# VoteWeighting — deployment and activation verification

**Result:** the historical VoteWeighting is deployed and active in the canonical Ethereum staking-incentive system. Its code matches the pre-May baseline. **The revised version is not active in this system at either checked block.** No separately deployed revised instance was found in the bounded discovery below; that does not prove no such deployment exists anywhere.

## Pins and scope

| Snapshot | Ethereum block | UTC time |
|---|---:|---|
| Original governance review | 26,032,428 | 2026-09-22 10:27:59 |
| Fresh verification | 26,034,116 | 2026-09-22 16:07:11 |

Block hashes, addresses, calls, source comparisons, repository commits and raw-input hashes are retained in [deployment-evidence.json](deployment-evidence.json). The [collector](verify_deployment.cjs) performs read-only RPC, GitHub and explorer requests; it does not sign or broadcast transactions. Raw responses are ignored under `data/`.

Here, **active** means selected by the canonical Treasury/Tokenomics/Dispenser wiring, with the Dispenser unpaused and observed recent use. It does not establish correct accounting, uninterrupted operation or absence of bugs.

## Which instance is actually used?

All of the following agree at both blocks:

| On-chain read | Returned address |
|---|---|
| Treasury `tokenomics()` | `0xc096362fa6f4A4B1a9ea68b1043416f3381ce300` |
| Treasury and Tokenomics `dispenser()` | `0x5650300fCBab43A0D7D02F8Cb5d0f039402593f0` |
| Dispenser `voteWeighting()` | **`0x95418b46d5566D3d1ea62C12Aea91227E566c5c1`** |
| That VoteWeighting's `dispenser()` | `0x5650300fCBab43A0D7D02F8Cb5d0f039402593f0` |
| That VoteWeighting's `ve()` | `0x7e01A500805f8A52Fad229b3015AD130A332B7b3` |

The collector also verifies Dispenser's reciprocal Treasury/Tokenomics links and consistent Timelock ownership. Dispenser `paused() = 0`; its verified deployed source defines enum value zero as `Unpaused`. The verified Dispenser source calls `checkpointNominee` and `nomineeRelativeWeight` on its configured `voteWeighting`, and authorizes nominee callbacks using that address. The links therefore determine its behavior rather than serving as informational registry entries.

Recent activity corroborates the wiring: over blocks **25,984,116–26,034,116**, the collector found five `CheckpointNominee` and four `VoteForNominee` events on the historical instance. The latest collected checkpoint is in a [successful transaction to the Dispenser](https://etherscan.io/tx/0xe7b171eae0ec04937e9f9d310e48c94c25a728f85ef9ab80e795c7b2ffe60339), block **26,013,988**; the collector matched the event to its transaction receipt. This is bounded evidence of use, not an exhaustive activity audit.

Primary contract references: [VoteWeighting verified source](https://etherscan.io/address/0x95418b46d5566D3d1ea62C12Aea91227E566c5c1#code), [Dispenser verified source](https://etherscan.io/address/0x5650300fCBab43A0D7D02F8Cb5d0f039402593f0#code). Historical getter results are pinned in the compact JSON; explorer read panels can show a later state.

## Is its code the revised version?

**No.** The explorer-published VoteWeighting source is byte-for-byte identical to `contracts/VoteWeighting.sol` at `v1.2.5-post-external-audit` (`b5875317d0de5c9a81b89e86ec8c16f72dff0b33`). It differs from the reviewed revised source at `93901ec315eb2b1d4683aab5615ef38b071228f8`.

| Property | Active historical instance | Revised source |
|---|---|---|
| Constructor | `(address _ve)` | `(address _ve, address _dispenser)` |
| Dispenser binding | Mutable; `changeDispenser` exists | Immutable; setter removed |
| Reviewed accounting fixes | Pre-fix baseline code | Fixes present in source |

The historical instance has **12,054 runtime bytes**, compiler **0.8.25**, optimizer **1,000,000 runs**, EVM **Cancun**. Its runtime hash is `0x9b18cc0eace5e55eb3d336f336b862a822e1e323ac723d851f51283c38b4bb86` at both blocks. The explorer's deployed bytecode matches the runtime obtained through RPC. The Dispenser's explorer/runtime match is checked separately.

This check relies on the explorer's source verification; it does not independently recompile the historical VoteWeighting with its original compiler settings. Exact baseline-source equality and the old constructor/setter distinguish this deployment from the revised implementation. It is not an upgradeable proxy that has silently adopted the revised code.

## Was a replacement deployed separately?

The discovery checked:

- [Governance mainnet configuration at `93901ec`](https://github.com/valory-xyz/autonolas-governance/blob/93901ec315eb2b1d4683aab5615ef38b071228f8/scripts/deployment/globals_mainnet.json).
- [Tokenomics mainnet configuration at `861d080`](https://github.com/valory-xyz/autonolas-tokenomics/blob/861d08007b0131e0aa3b2df4a6dd81aaea985992/scripts/deployment/globals_mainnet.json).
- The actual contract wiring above.
- [Blockscout contract-name search](https://eth.blockscout.com/api/v2/search?q=VoteWeighting): one exact `VoteWeighting` contract-name result, the historical instance, with no next page returned. The original response remains in the local collection; the search endpoint can change.

Both repositories' current main configurations still identify the historical instance. No revised address emerged from these sources. An unverified contract or an unannounced deployment under another name could be absent from them. Therefore record **“revised deployment not found; revised version not active in the checked canonical system”**, rather than “proved never deployed.”

## Effect on the review plan

- [x] Verify which VoteWeighting instance is active and identify its source version.
- [x] Check current published deployment records and exact-name explorer discovery for a replacement; none found within this scope.
- [ ] Review the source fixes and their regressions; distinguish verified source improvements from fixes active on-chain.

The security fixes identified in the revised VoteWeighting **cannot be described as deployed fixes for the active instance**. This deployment check does not repeat the accounting audit or determine the current impact of each historical defect.

## Reproduce

From the repository root, with its Node dependencies installed:

```sh
node audits/2026-09-22-governance-review/point-3/verify_deployment.cjs
```

The script uses saved local responses where present. A fresh clone uses the pins and repository commits from the committed result; archive RPC and public explorer/GitHub access are required to recollect inputs. Contract-name discovery is provider-dependent and is not historically pinned. `--refresh` explicitly selects a new current block and current repository heads; review resulting changes before publishing. The original governance pin remains unchanged. Source comparison uses the checkout's `VoteWeighting.sol`; its SHA-256 is recorded so a changed checkout cannot silently be mistaken for the reviewed revision.
