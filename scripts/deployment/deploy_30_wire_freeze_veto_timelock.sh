#!/bin/bash

# Wire the Veto-Governor into Veto Timelock, THEN freeze its roles forever (role-freeze section).
#
# Sequence (order is load-bearing — see the deploy-order constraint):
#   1. grantRole(PROPOSER_ROLE, vetoGovernor) on Veto Timelock
#         (needed: GovernorTimelockControl.queue → _timelock.scheduleBatch)
#   2. grantRole(EXECUTOR_ROLE, vetoGovernor) on Veto Timelock
#         (needed: GovernorTimelockControl._execute → _timelock.executeBatch)
#   3. grantRole(CANCELLER_ROLE, vetoGovernor) on Veto Timelock
#         (needed: GovernorCompatibilityBravo.cancel(uint256) reaches
#          GovernorTimelockControl._cancel → _timelock.cancel(id) whenever a veto proposal
#          is already queued on VT. queue() and execute() are separate permissionless txs,
#          so the queued-but-unexecuted window is unbounded — proposer self-withdrawal or
#          below-threshold cleanup would otherwise revert forever without this grant.)
#   4. revokeRole(TIMELOCK_ADMIN_ROLE, vetoTimelockAddress) — closes the self-administration hole
#         that would otherwise let ONE won veto vote grant an attacker standing PROPOSER on VT
#         (permanent, voteless griefing of every Timelock A op). Hard requirement.
#   5. renounceRole(TIMELOCK_ADMIN_ROLE, deployer) — deployer relinquishes its admin.
#
# The CANCELLER role the veto stack ALSO needs is on **Timelock A** (granted in Task 2),
# so VT can call A.cancel(badId) — orthogonal to the CANCELLER-on-VT grant above.
#
# After step 5, NO account holds TIMELOCK_ADMIN_ROLE on Veto Timelock — B's role set is frozen for
# life. Any future re-pointing requires redeploying a fresh B'. Note that `B.updateDelay(...)`
# is `onlySelf` (role-less), so a veto vote CAN still self-disarm B by bumping its minDelay
# above 0 (T9 residual) — recovery = redeploy B' + re-grant CANCELLER on Timelock A
# via one main-Governor cycle.
#
# Depends on: deploy_28_veto_timelock.sh + deploy_29_veto_governor.sh.

red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
reset=$(tput sgr0)

if [ -z "$1" ]; then
  echo "${red}!!! Usage: $0 <network>${reset}"
  echo "${red}Example: $0 mainnet${reset}"
  exit 1
fi

globals="$(dirname "$0")/globals_$1.json"
if [ ! -f $globals ]; then
  echo "${red}!!! $globals is not found${reset}"
  exit 0
fi

useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)

if [ $chainId == 1 ]; then
  API_KEY=$ALCHEMY_API_KEY_MAINNET
  if [ "$API_KEY" == "" ]; then
      echo "${red}!!! Set ALCHEMY_API_KEY_MAINNET env variable${reset}"
      exit 0
  fi
elif [ $chainId == 11155111 ]; then
    API_KEY=$ALCHEMY_API_KEY_SEPOLIA
    if [ "$API_KEY" == "" ]; then
        echo "${red}!!! Set ALCHEMY_API_KEY_SEPOLIA env variable${reset}"
        exit 0
    fi
fi

vetoTimelockAddress=$(jq -r '.vetoTimelockAddress' $globals)
vetoGovernorAddress=$(jq -r '.vetoGovernorAddress' $globals)
rpcURL="$networkURL$API_KEY"

if [ "$vetoTimelockAddress" == "null" ] || [ -z "$vetoTimelockAddress" ]; then
  echo "${red}!!! globals.vetoTimelockAddress is unset. Run deploy_28 first.${reset}"
  exit 0
fi
if [ "$vetoGovernorAddress" == "null" ] || [ -z "$vetoGovernorAddress" ]; then
  echo "${red}!!! globals.vetoGovernorAddress is unset. Run deploy_29 first.${reset}"
  exit 0
fi

if [ "$useLedger" == "true" ]; then
  walletArgs="-l --mnemonic-derivation-path $derivationPath"
  deployer=$(cast wallet address $walletArgs)
else
  echo "Using PRIVATE_KEY: ${PRIVATE_KEY:0:6}..."
  walletArgs="--private-key $PRIVATE_KEY"
  deployer=$(cast wallet address $walletArgs)
fi

echo "${green}Wiring + freezing from: $deployer${reset}"
echo "  Veto Timelock     : $vetoTimelockAddress"
echo "  Veto-Governor  : $vetoGovernorAddress"

adminRole=$(cast keccak "TIMELOCK_ADMIN_ROLE")
proposerRole=$(cast keccak "PROPOSER_ROLE")
executorRole=$(cast keccak "EXECUTOR_ROLE")
cancellerRole=$(cast keccak "CANCELLER_ROLE")

# Pre-condition: deployer must still hold TIMELOCK_ADMIN_ROLE on Veto Timelock.
deployerHasAdmin=$(cast call --rpc-url $rpcURL $vetoTimelockAddress "hasRole(bytes32,address)(bool)" $adminRole $deployer)
if [ "$deployerHasAdmin" != "true" ]; then
  echo "${red}!!! deployer does NOT hold TIMELOCK_ADMIN_ROLE on Veto Timelock.${reset}"
  echo "${red}    The freeze already ran or the deployer changed. Abort.${reset}"
  exit 0
fi

send() {
  local step="$1"; local sig="$2"; local addr="$3"; shift 3
  echo "${yellow}[$step] cast send $addr $sig $@${reset}"
  # HARD abort on any failed tx: without this, a failed grant would let the script fall
  # through to the IRREVERSIBLE revoke/renounce steps, leaving VT with no admin and no
  # proposer/executor/canceller.
  if ! cast send --rpc-url $rpcURL $walletArgs $addr "$sig" "$@" >/dev/null; then
    echo "${red}!!! [$step] cast send FAILED. Aborting BEFORE any subsequent step runs.${reset}"
    echo "${red}    Deployer still holds TIMELOCK_ADMIN_ROLE — re-run once the failure is fixed.${reset}"
    exit 1
  fi
}

# --- (1) grant PROPOSER to Veto-Governor ---
send "1/5 grant PROPOSER" "grantRole(bytes32,address)" $vetoTimelockAddress $proposerRole $vetoGovernorAddress
# --- (2) grant EXECUTOR to Veto-Governor ---
send "2/5 grant EXECUTOR" "grantRole(bytes32,address)" $vetoTimelockAddress $executorRole $vetoGovernorAddress
# --- (3) grant CANCELLER to Veto-Governor ---
#     Enables the Bravo cancel(uint256) path (proposer self-withdrawal, or anyone once
#     proposer drops below 5000 veOLAS) to clear a queued-but-unexecuted veto proposal
#     on VT. Frozen immutably in step 5; VT can only cancel proposals it itself queued.
send "3/5 grant CANCELLER" "grantRole(bytes32,address)" $vetoTimelockAddress $cancellerRole $vetoGovernorAddress

# --- (4) FREEZE — revoke Veto Timelock's own TIMELOCK_ADMIN_ROLE ---
# deployer is the ADMIN of ADMIN (OZ TimelockController._setRoleAdmin(TIMELOCK_ADMIN_ROLE, TIMELOCK_ADMIN_ROLE)),
# so deployer can revoke VT's self-admin here.
send "4/5 REVOKE VT self-admin (freeze)" "revokeRole(bytes32,address)" $vetoTimelockAddress $adminRole $vetoTimelockAddress

# --- (5) FREEZE — deployer renounces its own admin ---
send "5/5 renounce deployer admin (freeze)" "renounceRole(bytes32,address)" $vetoTimelockAddress $adminRole $deployer

echo ""
echo "${green}Post-freeze verification (all must match — abort ANY deviation before Task 2):${reset}"
propOK=$(cast call --rpc-url $rpcURL $vetoTimelockAddress "hasRole(bytes32,address)(bool)" $proposerRole $vetoGovernorAddress)
execOK=$(cast call --rpc-url $rpcURL $vetoTimelockAddress "hasRole(bytes32,address)(bool)" $executorRole $vetoGovernorAddress)
cancOK=$(cast call --rpc-url $rpcURL $vetoTimelockAddress "hasRole(bytes32,address)(bool)" $cancellerRole $vetoGovernorAddress)
selfAdm=$(cast call --rpc-url $rpcURL $vetoTimelockAddress "hasRole(bytes32,address)(bool)" $adminRole $vetoTimelockAddress)
depAdm=$(cast call --rpc-url $rpcURL $vetoTimelockAddress "hasRole(bytes32,address)(bool)" $adminRole $deployer)
minDelay=$(cast call --rpc-url $rpcURL $vetoTimelockAddress "getMinDelay()(uint256)" | awk '{print $1}')

echo "  hasRole(PROPOSER, vetoGov)         : $propOK   (must be true)"
echo "  hasRole(EXECUTOR, vetoGov)         : $execOK   (must be true)"
echo "  hasRole(CANCELLER, vetoGov)        : $cancOK   (must be true — Bravo cancel(uint256) path)"
echo "  hasRole(ADMIN, vetoTimelock) [FRZ] : $selfAdm  (must be false — role-freeze)"
echo "  hasRole(ADMIN, deployer)     [FRZ] : $depAdm   (must be false — deployer renounced)"
echo "  getMinDelay()                       : $minDelay (must be 0; monitor this — T9 alerts if != 0)"

if [ "$propOK" != "true" ] || [ "$execOK" != "true" ] \
   || [ "$cancOK" != "true" ] \
   || [ "$selfAdm" != "false" ] || [ "$depAdm" != "false" ]; then
  echo "${red}!!! Post-freeze verification FAILED. Do NOT proceed to Task 2.${reset}"
  echo "${red}    Investigate, revert if possible, or redeploy VT' from deploy_28.${reset}"
  exit 1
fi

echo ""
echo "${green}Task 1 complete. Veto stack deployed, wired, and frozen.${reset}"
echo "${green}Next: Task 2 — batched governance proposal on the main Governor:${reset}"
echo "    A.grantRole(CANCELLER_ROLE, $vetoTimelockAddress)"
echo "    Governor.setVotingDelay(72000)         # Layer 1 (~10 d pre-passage)"
echo "    Governor.updateGovernorDelay(1209600)  # Layer 2 (14 d post-passage)"
