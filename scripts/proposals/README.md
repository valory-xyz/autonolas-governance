# Governance proposals

Index of on-chain governance proposals prepared for the Olas DAO.

Going forward, each proposal lives in its own `proposal_<N>/` subfolder containing:
- the calldata builder (Forge script) and/or JS builder,
- an annotated, self-contained **HTML** breakdown (selectors, encoded arguments and addresses decoded and labelled, with the copy-paste `propose()` arrays and the pre-computed `proposalId`),
- a `description.txt` (the exact on-chain proposal description),
- a `README.md` describing the proposal.

Every proposal description must contain the sentence:
> In accordance with Autonolas DAO Constitution at ipfs://bafybeibrhz6hnxsxcbv7dkzerq4chssotexb276pidzwclbytzj7m4t47u

L1 effects are validated by Forge fork tests under [`test/proposals/`](../../test/proposals). L2 (bridged)
effects are validated separately via Tenderly simulations on the destination chain.

## Proposals

| # | Summary | Folder | Annotated HTML | Fork test (L1) |
|---|---------|--------|----------------|----------------|
| 11 | Olas Governance & GuardCM activation: migrate Timelock roles to the new GovernorOLAS, configure + swap in the new GuardCM, set new Celo BalanceTrackers, upgrade Tokenomics impl to v1.4.3 | [proposal_11/](proposal_11) | [proposal_11.html](proposal_11/proposal_11.html) | [Proposal11Activation.t.sol](../../test/proposals/Proposal11Activation.t.sol) |

### Legacy proposals

Proposals 01–10 are the standalone scripts in this directory (`proposal_01_*.js` … `proposal_10_*.js`),
which print `targets / values / calldatas / description` for a single action each. They predate the
per-folder + annotated-HTML convention.
