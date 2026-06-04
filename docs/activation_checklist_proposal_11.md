# Activation vote — PR #199 (new GovernorOLAS + GuardCM) + related upgrades

PR #199 only records deployed addresses in `globals_mainnet.json`. The contracts are deployed
with correct constructor params but **dormant**. This document is the full action list to activate
them, plus two related upgrades (marketplace Celo balance trackers, Tokenomics implementation).

All actions A–D + F are mainnet governance calls and **can be batched into a single proposal**
through whichever governor currently holds Timelock roles (today: the **old** governor
`0x8E84B5…3b401`, since the new one has no roles yet). E (Celo) is bridged but still a mainnet call,
so it can ride in the same proposal too.

## Addresses

| Role | Address |
|---|---|
| Timelock | `0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE` |
| **New** GovernorOLAS | `0x060D0CBdDFb0498d610E2EF55C01516B5B1251E6` |
| **Old** GovernorOLAS (governorTwo) | `0x8E84B5055492901988B831817e4Ace5275A3b401` |
| **New** GuardCM | `0xC0b146D61e2A2C17E024477E01978D1Fcf598c6B` |
| **Old** GuardCM | `0x7bB7998b210cFfE10ca1e41f16341Abe53f76f3a` |
| Community Multisig (CM, Gnosis Safe) | `0x04C06323Fe3D53Deb7364c0055E1F68458Cc2570` |
| TokenomicsProxy | `0xc096362fa6f4A4B1a9ea68b1043416f3381ce300` |
| Celo MechMarketplaceProxy | `0x17d96ba4532fe91809326092fE4D5606A7B7a0d8` |
| Celo L1CrossDomainMessenger (mainnet) | `0x1AC1181fc4e4F877963680587AEAa2C90D7EbB95` |
| Celo OptimismMessenger (L2 owner of marketplace) | `0xC14E191A64a7FB0e5790a8a0B9a58683dFFce04d` |

---

## A — Migrate Timelock roles to the new governor  ✅ template: `proposal_02_governor_to_governorTwo.js`

8 calls, **target = Timelock**, value 0. Mirrors the prior migration — note it includes
**`TIMELOCK_ADMIN_ROLE`** (confirmed on-chain: old gov holds it, new gov does not).
Roles: `TIMELOCK_ADMIN=keccak("TIMELOCK_ADMIN_ROLE")`, `PROPOSER=0xb09aa5ae…19cc1`,
`EXECUTOR=0xd8aa0f31…469e63`, `CANCELLER=0xfd643c72…26f783`.

- [ ] `grantRole(ADMIN, newGov)`, `grantRole(PROPOSER, newGov)`, `grantRole(EXECUTOR, newGov)`, `grantRole(CANCELLER, newGov)`
- [ ] `revokeRole(ADMIN, oldGov)`, `revokeRole(PROPOSER, oldGov)`, `revokeRole(EXECUTOR, oldGov)`, `revokeRole(CANCELLER, oldGov)`

---

## B — Bridge mediators on the new guard  ✅

`setBridgeMediatorL1BridgeParams(address[],address[],uint256[],address[])` (sel `0x1602c55c`),
owner-only (owner=Timelock). **target = new GuardCM**, value 0. Mirrors `script_26_01..04`.

All L1 and L2 mediator addresses below were **cross-checked against the canonical
`autonolas-tokenomics/scripts/deployment/staking` globals** and match exactly.
⚠️ **Mode is intentionally excluded** (being deprecated).

- [ ] Gnosis(100): L1 AMB `0x4C36…E64e` / verifier `0xDc87…4c48` / L2 HomeMediator `0x15bd…1776`
- [ ] Polygon(137): L1 FxRoot `0xfe5e…89a2` / verifier `0x133A…Dec3` / L2 FxGovernorTunnel `0x9338…755fD`
- [ ] Arbitrum(42161): L1 Inbox `0x4Dbd…aB3f` / verifier `0x0F33…44d4` / L2 `0x4d30…a70F`
- [ ] Optimism/Base/Celo(10/8453/42220): L1 [`0x25ac…5fA1`,`0x866E…0Afa`,`0x1AC1…bB95`] / verifier `0xdCAF…3Fb5` ×3 / L2 [`0x87c5…C60c`,`0xE49C…c8EA`,`0xC14E…04d2`]  *(Mode dropped)*

---

## C — Target-selector allow-list on the new guard

`setTargetSelectorChainIds(address[],bytes4[],uint256[],bool[])`, owner-only. **target = new GuardCM**.

**Current allow-list on the OLD guard (all verified active on-chain) — carry forward unless the team changes it:**

| Target | Selector | Function | chainId |
|---|---|---|---|
| Treasury `0xa0DA…0f82` | `0x8456cb59` | `pause()` | 1 |
| Treasury `0xa0DA…0f82` | `0x8f202bf9` | `drainServiceSlashedFunds()` | 1 |
| Depository `0xfF86…0C81` | `0x58d3ec6a` | `close(uint256[])` | 1 |
| ServiceRegistryTokenUtility `0x3Fb9…affA` | `0xece53132` | `drain(address)` | 1 |
| ServiceRegistryL2 (Polygon) `0xE360…4b50` | `0x9890220b` | `drain()` | 137 |
| ServiceRegistryL2 (Gnosis) `0x9338…755fD` | `0x9890220b` | `drain()` | 100 |
| ServiceRegistryTokenUtility (Gnosis) `0xa45E…18eD8` | `0xece53132` | `drain(address)` | 100 |

- [ ] **Team to confirm final list** (new guard supports Arbitrum/Optimism/Base/Celo too — add their service registries if desired), then encode with all statuses=true.

> ⚠️ **Verify every target on-chain — globals field names are misleading.** The tokenomics globals list
> two depositories; on-chain `Treasury.depository()` confirms the **LIVE Depository is `0xfF8697d8d2998d6AA2e09B405795C6F4BEeB0C81`**
> (owner = Timelock). The other, `0x52A043…aB3f`, is **abandoned (`owner()` = `0x…dEaD`)** — do NOT use it.
> The existing old-guard `close()` entry already points at the correct live `0xfF86…0C81`. Confirm each
> target with an authoritative getter (`Treasury.depository()`, `owner()`, `drainer()`), not field names.
>
> **Verified C address/ownership matrix (all on-chain):**
>
> Mainnet (chainId 1), owner = Timelock `0x3C1f…D95fE`:
> - Treasury `0xa0DA53447C0f6C4987964d8463da7e6628B30f82` — `pause()` 0x8456cb59, `drainServiceSlashedFunds()` 0x8f202bf9
> - Depository (LIVE) `0xfF8697d8d2998d6AA2e09B405795C6F4BEeB0C81` — `close(uint256[])` 0x58d3ec6a
> - ServiceRegistryTokenUtility (L1) `0x3Fb926116D454b95c669B6Bf2E7c3bad8d19affA` — `drain(address)` 0xece53132
> - (L1 ServiceRegistry `drain()` is NOT eligible — its drainer is the Treasury; use `drainServiceSlashedFunds()` instead.)
>
> L2 drain matrix — every SRL2.drainer()/SRTU.owner() == chain bridgeMediator (verified). `drain()` 0x9890220b, `drain(address)` 0xece53132:
>
> | Chain (id) | ServiceRegistryL2 | ServiceRegistryTokenUtility | bridgeMediator |
> |---|---|---|---|
> | Gnosis (100) | `0x9338b5153AE39BB89f50468E608eD9d764B755fD` | `0xa45E64d13A30a51b91ae0eb182e88a40e9b18eD8` | `0x15bd…1776` |
> | Polygon (137) | `0xE3607b00E75f6405248323A9417ff6b39B244b50` | `0xa45E64d13A30a51b91ae0eb182e88a40e9b18eD8` | `0x9338…755fD` |
> | Arbitrum (42161) | `0xE3607b00E75f6405248323A9417ff6b39B244b50` | `0x3d77596beb0f130a4415df3D2D8232B3d3D31e44` | `0x4d30…a70F` |
> | Optimism (10) | `0x3d77596beb0f130a4415df3D2D8232B3d3D31e44` | `0xBb7e1D6Cb6F243D6bdE81CE92a9f2aFF7Fbe7eac` | `0x87c5…C60c` |
> | Base (8453) | `0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE` | `0x34C895f302D0b5cf52ec0Edd3945321EB0f83dd5` | `0xE49C…c8EA` |
> | Celo (42220) | `0xE3607b00E75f6405248323A9417ff6b39B244b50` | `0x3d77596beb0f130a4415df3D2D8232B3d3D31e44` | `0xC14E…04d2` |
>
> (Base addresses coincide with L1 governance addresses via CREATE2 — distinct contracts, verified.)

---

## D — Swap the guard on the CM via the Timelock module  ✅ template: `proposal_05_CM_guard.js`

The Timelock is an **enabled Safe module** on the CM (verified: it's the only module). So governance
makes the CM swap its own guard — no CM-signer action needed. **target = CM**, value 0:

```
CM.execTransactionFromModule(to=CM, value=0, data=CM.setGuard(newGuard), operation=Call)
```
- [ ] Encode `setGuard(0xC0b146…8c6B)` then wrap in `execTransactionFromModule`.
- [ ] Sequence after B+C so the CM is never under an unconfigured guard.

---

## E — Set new Celo BalanceTrackers on MechMarketplaceProxy (bridged)

Bridged action: mainnet governance → Celo L1CrossDomainMessenger → Celo OptimismMessenger →
`setPaymentTypeBalanceTrackers(bytes32[],address[])` (sel `0xd64bf8b0`, owner-only; owner = the Celo
OptimismMessenger). **target = Celo L1CrossDomainMessenger `0x1AC1…bB95`**, value 0.

Payment type hashes: Native `0xba699a34…abed1`, OLAS `0x3679d66e…45e9`, USDC `0x6406bb5f…d5e3`.

- [x] New Celo BalanceTracker addresses confirmed brand-new (have code on Celo; differ from on-chain registered):
      Native `0x2E008211f34b25A7d7c102403c6C2C3B665a1abe` (was `0x9311…3a54`),
      OLAS `0xB3921F8D8215603f0Bd521341Ac45eA8f2d274c1` (was `0x3912…1F43`),
      USDC `0x97371B1C0cDA1D04dFc43DFb50a04645b7Bc9BEe` (was `0xA749…0fF8`).
- [ ] Build inner `setPaymentTypeBalanceTrackers([nativeHash,olasHash,usdcHash],[native,olas,usdc])`.
- [ ] Pack L2 data `target(20)+value(uint96)+len(uint32)+payload`, wrap in `processMessageFromSource(bytes)` (to Celo OptimismMessenger `0xC14E…04d2`), wrap in `sendMessage(address,bytes,uint32)` minGas≈2,000,000.
- [ ] Verify Celo proxy `owner()` is `0xC14E…04d2` and that messenger's source governor is the mainnet Timelock.

---

## F — Update Tokenomics implementation on TokenomicsProxy

`changeTokenomicsImplementation(address)` (sel `0x590a92d0`), owner-only (owner = Timelock).
**target = TokenomicsProxy `0xc096…e300`**, value 0. Template: tokenomics repo
`scripts/proposals/proposal_01_change_tokenomics_implementation.js`. No post-upgrade initializer needed
(state persists in proxy; v1.4.3 diff is the `checkpoint` effectiveBond fix only).

- [x] New impl confirmed deployed on mainnet: `0xaeeC8bC8E5Fe28BC4dF2e9586b222924b8a0d5e9`
      (has code, 19,602 bytes; differs from live impl `0x1ce191601e7f2777EEB797149d6e65aE40dF0e93`).
- [ ] calldata = `changeTokenomicsImplementation(0xaeeC…d5e9)` =
      `0x590a92d0000000000000000000000000aeec8bc8e5fe28bc4df2e9586b222924b8a0d5e9`, target = TokenomicsProxy `0xc096…e300`.

---

## Post-activation verification
- [ ] `hasRole(ADMIN/PROPOSER/EXECUTOR/CANCELLER, newGov)`==true and ==false for oldGov
- [ ] New guard bridge params + target selectors read back correct; CM guard slot == new guard
- [ ] Celo proxy `mapPaymentTypeBalanceTrackers(<hash>)` == new trackers (after bridge relay)
- [ ] TokenomicsProxy `tokenomicsImplementation()` == new impl
- [ ] Smoke-test a full proposal lifecycle on the **new** governor (propose → queue → execute)
