# Deployment scripts
This folder contains the scripts to deploy Autonolas governance. These scripts correspond to the steps in the full deployment procedure (as described in [deployment.md](docs/deployment.md)).

## Observations
- There are several files with global parameters based on the corresponding network. In order to work with the configuration, please copy `gobals_network.json` file to file the `gobals.json` one, where `network` is the corresponding network. For example: `cp gobals_mainnet.json gobals.json`.
- The Valory multisig (Valory) is a Gnosis Safe contract with 3 signers and 2 threshold that already exists.
- The community multisig (CM) of the DAO is a Gnosis Safe contract with 9 signers and 6 threshold that already exists.
- Please note: if you encounter the `Unknown Error 0x6b0c`, then it is likely because the ledger is not connected or logged in.

## Steps to engage
The project has submodules to get the dependencies. Make sure you run `git clone --recursive` or init the submodules yourself.
The dependency list is managed by the `package.json` file, and the setup parameters are stored in the `hardhat.config.js` file.
Simply run the following command to install the project:
```
yarn install
```
command and compiled with the
```
npx hardhat compile
```
command as described in the [main readme](README.md).


Create a `globals.json` file in the root folder, or copy it from the file with pre-defined parameters (i.e., `scripts/deployment/globals_mainnet.json` for the mainnet).

Parameters of the `globals.json` file:
- `contractVerification`: a flag for verifying contracts in deployment scripts (`true`) or skipping it (`false`);
- `useLedger`: a flag whether to use the hardware wallet (`true`) or proceed with the seed-phrase accounts (`false`);
- `valoryMultisig`: a Valory multisig address;
- `derivationPath`: a string with the derivation path;
- `CM`: a Community multisig address;
- `providerName`: a network type (see `hardhat.config.js` for the network configurations).

Other values are related to the governance and initial mint. The Gnosis Safe contracts are also provided for convenience. The deployed contract addresses will be added / updated during the scripts run.

The script file name identifies the number of deployment steps taken up to the number in the file name. For example:
- `deploy_02_deployment_factory.js` will complete step 2 from [deployment.md](docs/deployment.md) (1 is already complete as the multisig is created beforehand);
- `deploy_08_09_governor_and_roles.js` will complete steps 8 and 9;
- etc.

NOTE: All the scripts MUST be strictly run in the sequential order from smallest to biggest numbers.

Export network-related API keys defined in `hardhat.config.js` file that correspond to the required network.

To run the script, use the following command:
`npx hardhat run scripts/deployment/script_name --network network_type`,
where `script_number_and_name` is a script number and name, i.e. `deploy_02_deployment_factory.js`, `network_type` is a network type corresponding to the `hardhat.config.js` network configuration.

## Validity checks and contract verification
Each script controls the obtained values by checking them against the expected ones. Also, each script has a contract verification procedure.
If a contract is deployed with arguments, these arguments are taken from the corresponding `verify_number_and_name` file, where `number_and_name` corresponds to the deployment script number and name.

## Deployment of supplemental contracts
For deploying supplemental contracts listed in [deployment.md](docs/deployment.md),
run the following scripts:
```
npx hardhat run scripts/deployment/deploy_16_wveolas.js --network network_type
npx hardhat run scripts/deployment/deploy_17_governorTwo.js --network network_type
```

Then, after successful deployment of two supplemental contracts, the last script gives the proposal payload necessary to finalize the deployment:
`npx hardhat run scripts/deployment/deploy_18_governor_to_governorTwo.js --network network_type`.

## Deployment of VoteWeighting

`VoteWeighting` is an Ethereum **mainnet** contract: it binds `veOLAS` (L1-only) and the L1
`Dispenser` immutably in its constructor, so it is deployed against `globals_mainnet.json`
(`chainId` 1) and not on any L2.

### Get into a deployable state

```bash
git clone --recursive git@github.com:valory-xyz/autonolas-governance.git
cd autonolas-governance
yarn
foundryup
forge build
```

Export the original-Etherscan `ETHERSCAN_API_KEY` (used by `forge verify-contract`) and the
`ALCHEMY_API_KEY_MAINNET` key the script appends to `networkURL`.

### Required before deploying — identify the Dispenser proxy and implementation

This shell flow uses the **new Dispenser proxy**, even while the old Dispenser remains active.
Deploy and audit the implementation/proxy in
[autonolas-tokenomics](https://github.com/valory-xyz/autonolas-tokenomics) first. Manually copy:

| Tokenomics `scripts/deployment/globals_mainnet.json` | Governance `scripts/deployment/globals_mainnet.json` |
|---|---|
| `dispenserProxyAddress` | `dispenserAddress` — VoteWeighting constructor argument |
| `dispenserAddress` | `dispenserImplementationAddress` — expected reviewed implementation, used only for validation |

Neither governance key is prefilled. Check both values against the audited deployment; do not copy the
implementation into governance's `dispenserAddress`. VoteWeighting's binding is immutable.
The shell script checks the RPC chain, contract code, the proxy's `PROXY_DISPENSER` storage slot against
`dispenserImplementationAddress`, and a nonzero proxy owner before broadcasting. A nonzero owner alone
is insufficient: a standalone implementation may have been initialized. These identity checks do not
replace the tokenomics audit of the reviewed implementation and proxy configuration.

A fresh proxy has `voteWeighting() == 0`; this is expected and does not prevent VoteWeighting deployment.
Use the shell command below for this flow; the legacy Hardhat deployment helper does not perform these
proxy checks.

### Deploy

```bash
./scripts/deployment/deploy_23_vote_weighting.sh mainnet
```

The script pre-flights the dispenser (above), deploys `contracts/VoteWeighting.sol`, writes
`voteWeightingAddress` back into `globals_mainnet.json` (**overwriting** the previous
VoteWeighting address), asserts the deployed `ve()` / `dispenser()` / `owner()` against the
expected values, and verifies the contract on Etherscan (plus Blockscout when `blockscoutURL`
is set). The post-deploy asserts only *report* a wrong immutable — the pre-flight is what can
still prevent it.

### After deployment — audit and hand back the VoteWeighting address

Update the `VoteWeighting` entry in `docs/configuration.json` with the deployed address and its matching
artifact, then run the existing read-only chain audit:

```bash
node scripts/audit_chains/audit_contracts_setup.js
```

It compares VoteWeighting's immutable `ve()` and `dispenser()` with governance globals and retains the
owner/code checks. Before ownership handover, the deployer-versus-Timelock owner mismatch is expected;
the immutable bindings must already match. Missing/incorrect bindings are reported using the existing
audit reporting; inspect those findings as well as the exit status. No governance call can repair them.

Manually copy governance's `voteWeightingAddress` into tokenomics'
`scripts/deployment/globals_mainnet.json` under the same key. This is needed for the later
`script_dispenser_change_managers.sh` or governance payload calling
`newDispenserProxy.changeManagers(address(0), newVoteWeighting)`, not for deploying the Dispenser proxy.
Confirm explorer verification and the audit findings before ownership handover and activation.
See the [tokenomics migration runbook](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/docs/dispenser_migration_runbook_public.md)
for subsequent wiring; this configuration handoff performs no activation.

### VoteWeighting ownership handover

**Only transfer ownership after the deployment audit and explorer verification have been reviewed and every
unexpected finding resolved.** Confirm the immutable bindings and the intended `timelockAddress`, then complete
the address handoff above. `deploy_23_vote_weighting.sh` does not transfer ownership.

While the deployer still owns VoteWeighting, run from the repository root:

```bash
bash scripts/deployment/script_vote_weighting_change_owner.sh mainnet
```

The script reads `voteWeightingAddress`, `timelockAddress` and the chain/wallet settings from the network globals.
It checks the RPC chain, code at both addresses and that the signer is the current owner, calls
`changeOwner(timelockAddress)`, waits for a successful receipt, and verifies `owner()` against the Timelock.
It supports the same Ledger or `PRIVATE_KEY` signing choice as deployment. No DAO proposal is needed for this
transfer while the deployer owns the contract. An already-matching owner causes no transaction.
Rerun the read-only audit afterwards; the owner mismatch must disappear. This transfer does not activate tokenomics.

Focused local regression (fake deployment tools and a local audit fixture; no live transactions):

```bash
npx hardhat test test/Deployment.js --grep "VoteWeighting deployment checks"
```

### Push back the changes

```bash
git checkout -b vw_deployment
git commit -am "chore: deployment of VoteWeighting contract"
git push origin vw_deployment
```

## Deployment of the Veto stack (Task 1)

A cancel-only Veto-Governor bound to a dedicated Veto Timelock. Both contracts are
copies of the audited `Timelock` / `GovernorOLAS` bytecode already used by the main
stack — only the constructor parameters change.

Three shell scripts, run in strict order (each writes its address back to
`globals_<network>.json` for the next):

```bash
# Task 1 — deploy the veto stack
./scripts/deployment/deploy_28_veto_timelock.sh <network>
./scripts/deployment/deploy_29_veto_governor.sh <network>
./scripts/deployment/deploy_30_wire_freeze_veto_timelock.sh <network>
```

Deploy order is load-bearing:

1. **`deploy_28`** — deploy Veto Timelock empty (no proposers/executors — the Veto-Governor
   doesn't exist yet). Deployer holds `TIMELOCK_ADMIN_ROLE`.
2. **`deploy_29`** — deploy Veto-Governor bound to Veto Timelock. Its constructor reads
   `B.getMinDelay()`, so B must exist. The script sanity-checks `veto.token()` against the
   live main `Governor.token()` (must be the **wveOLAS wrapper `0x4039…`**, not raw veOLAS —
   the wveOLAS-wrapper token check). It also asserts the veto-cycle invariant
   `(vetoVotingDelay + vetoVotingPeriod) * 12 s + margin ≤ 1209600 s (14 d)` — the veto
   cycle MUST fit within the raised main `governorDelay` window (Task-2 target). The
   check is against the design constant, not live main state, so it stays correct through
   B′-recovery (when live main `votingDelay = 72000` — never copy that into the veto).
3. **`deploy_30`** — wire and **role-freeze** Veto Timelock, in this exact order:
   `grantRole(PROPOSER, VetoGov)` → `grantRole(EXECUTOR, VetoGov)` →
   `grantRole(CANCELLER, VetoGov)` → `revokeRole(TIMELOCK_ADMIN_ROLE, VT)` →
   `renounceRole(TIMELOCK_ADMIN_ROLE, deployer)`.
   After the freeze **no role on VT can ever change again** (hard requirement —
   closes the self-administration hole where one won veto vote would otherwise mint an
   attacker a standing PROPOSER). CANCELLER on VT is granted so
   `GovernorCompatibilityBravo.cancel(uint256)` can reach `_timelock.cancel` during the
   (unbounded) queued-but-unexecuted window — restores proposer self-withdrawal and
   below-threshold cleanup. VT can only cancel proposals it itself queued, so the grant
   adds no new attack surface.

**After Task 1** — Task 2 is a single batched proposal on the main Governor
(`Timelock A.grantRole(CANCELLER_ROLE, Veto Timelock)` + `setVotingDelay(72000)` +
`updateGovernorDelay(1209600)`).

### Running the fork tests

`test/forge/ForkGovernanceVetoDelay.t.sol` is a mainnet-fork verification of the veto
stack. It (and the pre-existing `ForkDeployGovernance.t.sol`) depend on `forge-std`,
which is tracked as a submodule pinned to `v1.9.7` (see `.gitmodules`).

Fresh clone:

```bash
git clone --recursive git@github.com:valory-xyz/autonolas-governance.git
```

Existing clone that pre-dates the submodule:

```bash
git submodule update --init --recursive
```

Then:

```bash
ETH_RPC_URL=<mainnet-rpc-url> forge test --match-contract ForkGovernanceVetoDelay -vv
```

Expected: **12/12 PASS**. Public RPCs (e.g. `https://ethereum-rpc.publicnode.com`) work
but are slow; Alchemy/Infura recommended.

Relevant `globals_<network>.json` keys (all pre-populated for mainnet):

| Key | Meaning |
|---|---|
| `vetoMinDelay` | Veto Timelock's `minDelay` — always `0` (instant cancels). |
| `vetoGovernorDelay` | Veto-Governor's `governorDelay` — always `0` (instant queue→execute). |
| `vetoVotingDelay` / `vetoVotingPeriod` | Kept at today's main values (13091 / 19636); NOT the raised Layer-1 value. |
| `vetoQuorum` / `vetoProposalThreshold` | Identical to main (3 % / 5,000 veOLAS). |
| `vetoTimelockAddress` / `vetoGovernorAddress` | Populated by `deploy_28` / `deploy_29`. |

## Deployment of Polygon-Ethereum ERC20 bridging contracts
For deploying ERC20 bridging contracts listed in [deployment.md](docs/deployment.md),
run the following scripts:
```
npx hardhat run scripts/deployment/deploy_19_bridged_erc20.js --network mainnet
npx hardhat run scripts/deployment/bridges/polygon/deploy_03_erc20_child_tunnel.js --network polygon
npx hardhat run scripts/deployment/deploy_20_erc20_root_tunnel.js --network mainnet
npx hardhat run scripts/deployment/deploy_21_22_bridged_erc20_change_owners.js --network mainnet
npx hardhat run scripts/deployment/bridges/polygon/deploy_04_set_root_tunnel.js --network polygon
```






