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

### REQUIRED before deploying — set `dispenserAddress`

`scripts/deployment/globals_mainnet.json` has **no `dispenserAddress` key**, and
`deploy_23_vote_weighting.sh` aborts on a missing/zero value by design. Add it, set to the
**current live Dispenser** address from the
[autonolas-tokenomics](https://github.com/valory-xyz/autonolas-tokenomics) repo's
`scripts/deployment/globals_<network>.json`.

**Which key holds that address depends on whether the proxied-Dispenser migration has happened
yet** — and the meaning of `dispenserAddress` on the tokenomics side flips at that point:

| State of the tokenomics repo | Live Dispenser = key | Do **not** copy |
|---|---|---|
| Before the migration (**today**) | `dispenserAddress` | — (`dispenserProxyAddress` does not exist yet) |
| After `deploy_07b_dispenser_proxy.sh` has run | `dispenserProxyAddress` (the `DispenserProxy`) | `dispenserAddress` — from then on it is the Dispenser **implementation** |

Copying the implementation address post-migration binds VoteWeighting to a contract with no
live state, and is only fixable by redeploying VoteWeighting. The cross-repo handoff is
described from the tokenomics side in its
[Dispenser migration runbook](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/docs/dispenser_migration_runbook_public.md)
(step 9 deploys VoteWeighting against the step-8 proxy).

Re-check the value on **every** run: whenever new Dispenser contracts are deployed, the live
address changes, and VoteWeighting stores the dispenser as an **immutable**.

```bash
# in autonolas-governance, with <liveDispenser> copied from the tokenomics globals per the table above
jq '.dispenserAddress = "<liveDispenser>"' scripts/deployment/globals_mainnet.json > tmp \
  && mv tmp scripts/deployment/globals_mainnet.json
```

Before broadcasting, the script pre-flights the address: it must have contract code, and it must
read a non-zero `owner()` — a bare Dispenser implementation reads `owner() == 0`, because the
implementation constructor sets immutables only and `initialize()` is delegatecalled by the
`DispenserProxy` constructor. `voteWeighting()` is printed but not asserted: a freshly deployed
proxy is initialized with `voteWeighting == 0` on purpose (VoteWeighting does not exist yet — it
binds the proxy), so it cannot discriminate.

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






