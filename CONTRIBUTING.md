# Contributing to `autonolas-governance`

First off, thank you for taking the time to contribute! This document describes how to propose changes, report issues,
and participate in the development of this repository.

> This guide is intentionally generic and applicable to Solidity projects that use **Foundry** and/or **Hardhat**. Replace placeholders (e.g., emails, URLs) with your project’s actual values as needed.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Repository Structure](#repository-structure)
- [How Can I Contribute?](#how-can-i-contribute)
  - [Reporting Bugs](#reporting-bugs)
  - [Suggesting Enhancements](#suggesting-enhancements)
  - [Security & Responsible Disclosure](#security--responsible-disclosure)
  - [Pull Requests](#pull-requests)
- [Development Setup](#development-setup)
  - [Prerequisites](#prerequisites)
  - [Install](#install)
  - [Build](#build)
  - [Test](#test)
  - [Lint & Static Analysis](#lint--static-analysis)
- [Solidity Style Guide](#solidity-style-guide)
- [Testing Guidelines](#testing-guidelines)
- [Commit Messages & Branching](#commit-messages--branching)
- [Versioning & Releases](#versioning--releases)
- [License & CLA/DCO](#license--cladco)
- [Contact](#contact)

---

## Code of Conduct

This project adheres to the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/) Code of Conduct. By participating, you are expected to uphold this code. Please report unacceptable behavior to **security@valory.xyz**.

---

## Repository Structure

Common top-level directories include:

- `contracts/` — Solidity source code.
- `test/` — Tests (JS/TS for Hardhat, `.t.sol` for Foundry, integration tests).
- `docs/` — Project related documentation and smart contract addresses.
- `scripts/` — Deployment and maintenance scripts (bash, TS/JS, etc.).
- `lib/` — External libraries (submodules or packages).
- `audits/` — Security reviews and reports (if any).
- `README.md` — Project overview and build instructions.

> The exact structure may differ; consult `README.md` for authoritative information.

---

## How Can I Contribute?

### Reporting Bugs

1. **Search existing issues** to avoid duplicates.
2. **Open a new issue** with a clear title and description.
3. Include steps to reproduce, expected vs actual behavior, logs, and environment details (OS, Node.js, Foundry, Solidity versions).

### Suggesting Enhancements

- Explain the motivation and expected impact.
- Provide a minimal example or pseudo-code.
- Consider compatibility and security implications.

### Security & Responsible Disclosure

**Do not** open public GitHub issues for security vulnerabilities. Instead:

- Email **security@valory.xyz** with a detailed report.
- Include steps to reproduce, the affected components, and potential impact.
- If you propose a fix, include a patch or PR against a private fork when appropriate.

We aim to acknowledge receipt within 72 hours. Disclosure timelines will be coordinated with you.

> Optional: link to a bug bounty policy if available.

### Pull Requests

1. Fork the repo and create your branch from `main`.
2. If you’ve added code that should be tested, add tests.
3. Ensure tests pass locally and CI is green.
4. Add/adjust documentation (README, NatSpec) as needed.
5. Use [Conventional Commits](https://www.conventionalcommits.org/) (see below).
6. Open a PR with a clear description of the change and reasoning.

**PR Checklist:**

- [ ] Self-reviewed, no debug prints or dead code.
- [ ] Tests: unit + fuzz/invariant where applicable.
- [ ] Gas impact considered; include `forge snapshot` diff if relevant.
- [ ] No storage layout breaking changes unless explicitly intended (document in PR).
- [ ] Public/External functions have NatSpec `@notice`/`@dev` and events where appropriate.
- [ ] No unguarded external calls; CEI (Checks-Effects-Interactions) respected.
- [ ] Access control and upgradability changes documented.

---

## Development Setup

### Prerequisites

- **Node.js** >= 18 and **npm** or **yarn**
- **Foundry** (`forge`, `cast`): https://getfoundry.sh
- **Hardhat** (optional): installed via `npm`/`yarn`
- **Solidity** compiler handled via Foundry/Hardhat toolchains

### Install

```bash
# clone
git clone https://github.com/<org>/<repo>.git
cd <repo>

# install JS deps (if applicable)
yarn install
# or
npm install
```

### Build

```bash
# Foundry
forge build

# Hardhat
yarn hardhat compile
# or
npx hardhat compile
```

### Test

```bash
# Foundry (unit & fuzz)
forge test -vvv

# With gas snapshots
forge snapshot

# Hardhat (JS/TS)
yarn hardhat test
# or
npx hardhat test
```

> Tip: Set `FOUNDRY_PROFILE=ci` or similar profiles in `foundry.toml` to standardize CI runs.

### Lint & Static Analysis

Recommended (enable what your project uses):

- **solhint** / **solium** for Solidity style/linting
- **prettier-plugin-solidity** for formatting
- **eslint**/**prettier** for JS/TS
- **slither** for static analysis (https://github.com/crytic/slither)
- **forge fmt** for formatting (Foundry)

Example:

```bash
# Lint solidity (if solhint configured)
npx solhint 'contracts/**/*.sol'

# Format solidity with prettier
npx prettier --write 'contracts/**/*.sol'

# Run slither (requires python env)
slither .
```

---

## Solidity Style Guide

- **SPDX** identifier at the top of each contract.
- **Pragmas** pinned or range-constrained consistently (e.g., `^0.8.24`).
- **NatSpec** for all public/external functions and events (`@notice`, `@dev`, `@param`, `@return`).
- **Custom errors** instead of string `revert` for gas and clarity.
- **Events**: emit on state changes that matter for off-chain monitoring; avoid “dangling” events (declared but never emitted).
- **Access control**: clear roles (`owner`, `guardian`, etc.), minimize privileges, prefer `onlyRole` pattern or equivalent.
- **CEI pattern** (Checks-Effects-Interactions) to reduce reentrancy risk.
- **Upgradeability**: if using proxies, document storage layout and upgrade steps; avoid storage collisions.
- **Math**: use safe libraries (e.g., OpenZeppelin/Solmate) and avoid silent overflows; consider `unchecked` only when safe and documented.
- **Interfaces**: prefer minimal interfaces for external calls.
- **Naming**: follow established conventions (`CamelCase` contracts, `mixedCase` functions/vars, `ALL_CAPS` constants).

---

## Testing Guidelines

- **Unit tests** for each contract; cover happy/sad paths.
- **Fuzz tests** (`forge`) to explore edge cases automatically.
- **Property-based / invariant tests** for protocol-level invariants.
- **Integration tests** for cross-contract and cross-chain flows if applicable.
- **Gas**: watch regressions using `forge snapshot` deltas.
- **Coverage**: target high logical coverage; justify gaps (e.g., defensive code).

Suggested structure:

```
test/
  Unit/
    ContractA.t.sol
  Integration/
    LiquidStaking.js
  Invariants/
    Invariant_Pps.t.sol
```

---

## Commit Messages & Branching

- Use **Conventional Commits**:
  - `feat: ...`, `fix: ...`, `docs: ...`, `refactor: ...`, `test: ...`, `chore: ...`, `perf: ...`
- Branch names:
  - `feat/<short-topic>`, `fix/<short-topic>`, `docs/<short-topic>`
- Reference issues/PRs in the body (e.g., `Closes #123`).

> Optionally enforce **DCO** (`Signed-off-by`) or a **CLA** as part of CI.

---

## Versioning & Releases

- Use **SemVer** where applicable.
- Tag releases (e.g., `v1.2.3`).
- For upgradeable deployments, include a migration plan and storage layout diff in release notes.
- Provide addresses/chain IDs and verification links when deployments are in scope.

---

## License & CLA/DCO

- This project is licensed under **MIT** (or your chosen license). See `LICENSE`.
- If required, contributors must sign a **CLA** or use **DCO** sign-offs. Document the process in this section or link to your CLA portal.

---

## Contact

- General questions: **info@valory.xyz**
- Security: **security@valory.xyz**

Thank you for contributing! 🚀
