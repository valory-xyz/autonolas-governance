# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Autonolas governance contracts: OLAS ERC20 token, voting escrow (veOLAS), OpenZeppelin Governor, cross-chain bridge messengers, and community multisig guard (GuardCM). Solidity ^0.8.15+, built with Hardhat, tested with Mocha/Chai/ethers.js v5.

## Build & Test Commands

```bash
# Install (requires Node v18.17+, yarn or npm)
yarn install

# Compile contracts (Solidity 0.8.30, optimizer 1M runs, EVM prague)
npx hardhat compile

# Run all tests
npx hardhat test

# Run a single test file
npx hardhat test test/veOLAS.js

# Code coverage
npx hardhat coverage

# Lint JavaScript (4-space indent, double quotes, semicolons, camelCase)
./node_modules/.bin/eslint . --ext .js,.jsx,.ts,.tsx

# Lint Solidity
./node_modules/.bin/solhint contracts/interfaces/*.sol contracts/*.sol contracts/test/*.sol

# Fork tests (compare veOLAS against live Curve veCRV, needs ALCHEMY_API_KEY)
npm run fork
```

## Architecture

**Token & Governance Stack:**
- `OLAS.sol` — ERC20 token with time-capped minting (solmate ERC20 base)
- `veOLAS.sol` — Voting escrow (Curve-style lock-for-vote-weight), implements IVotes
- `wveOLAS.sol` — Read-only wrapper around veOLAS with corrected view functions
- `GovernorOLAS.sol` — OpenZeppelin Governor composite (quorum, counting, timelock, votes)
- `Timelock.sol` — OpenZeppelin TimelockController wrapper
- `VoteWeighting.sol` — Curve-style gauge controller for vote allocation across nominees

**Cross-Chain Bridges** (`contracts/bridges/`):
- Polygon: `FxGovernorTunnel.sol`, `FxERC20ChildTunnel.sol`, `FxERC20RootTunnel.sol` (FxPortal)
- Gnosis: `HomeMediator.sol` (AMB)
- Optimism/Base: `OptimismMessenger.sol` (L1CrossDomainMessenger)
- Wormhole (Celo, etc.): `WormholeMessenger.sol`, `WormholeRelayerTimelock.sol`
- `BridgedERC20.sol` — Wrapped OLAS on child chains

**Multisig Guard** (`contracts/multisigs/`):
- `GuardCM.sol` — Transaction guard for community multisig, validates Timelock operations
- `VerifyData.sol` / `VerifyBridgedData.sol` — Data verification for L1 and bridged calls
- `ProcessBridgedData{Arbitrum,Gnosis,Optimism,Polygon,Wormhole}.sol` — Chain-specific bridge data processors

**Key Dependencies:** OpenZeppelin 4.8.3 (pinned), solmate (lib/ submodule), fx-portal, Gnosis Safe contracts.

## Solidity Conventions

These patterns are intentional project choices (see `docs/optimizations.md`):

- **No modifiers** — explicit inline checks to reduce bytecode
- **Custom reverts only** — no `require`/`assert`, use custom error types
- **No safeTransfer** — OLAS is trusted ERC20, no need for SafeERC20
- **CEI pattern** — Checks-Effects-Interactions ordering throughout
- **Memory caching** — storage vars loaded to memory for operations, written back after
- **Unchecked blocks** — only where safe, always with comments explaining why
- **No upgradeable proxies** — direct deployment
- **Addresses over interfaces** — use `address` type, cast when calling

## Deployment

Sequential numbered scripts in `scripts/deployment/` (deploy_02 through deploy_25+). Each reads/writes `globals.json` (copied from `globals_mainnet.json` or `globals_sepolia.json`). Run with:

```bash
npx hardhat run scripts/deployment/deploy_XX_name.js --network <network>
```

Bridge-specific deployments are in `scripts/deployment/bridges/{polygon,gnosis,optimism,wormhole}/`.

## CI

GitHub Actions (`.github/workflows/workflow.yaml`): eslint → solhint → hardhat test → hardhat coverage → codecov upload. Gitleaks secret scanning runs in parallel.