#!/bin/bash

# Deploy Veto-Governor — a redeploy of GovernorOLAS bound to Veto Timelock.
#
# Configuration:
#   token             = wveOLASAddress  — MUST be the wveOLAS WRAPPER (0x4039…), not raw
#                       veOLAS (0x7e01…). The main Governor votes on the wrapper; the veto
#                       must too or its tallies diverge silently (the wveOLAS-wrapper token check).
#   timelock          = vetoTimelockAddress  — the cancel-only timelock from deploy_28.
#   initialVotingDelay/Period = vetoVotingDelay / vetoVotingPeriod  — KEEP TODAY'S values
#                       (13091 / 19636 blocks ≈ 4.55 d cycle). Do NOT copy the raised
#                       Layer-1 votingDelay (72000) or the veto cycle overflows the 14 d
#                       governorDelay window.
#   quorum/threshold  = vetoQuorum / vetoProposalThreshold  — identical to main (3 % / 5000).
#                       Under Bravo counting the binding constraint is For > Against; the
#                       fresh snapshot is the veto's only edge.
#   governorDelay     = vetoGovernorDelay  — the Veto-Governor's own queue→execute delay,
#                       set to 0 so a passing veto executes instantly through Veto Timelock
#                       (whose minDelay is also 0). (role-freeze section).
#
# Constructor sig (GovernorOLAS.sol):
#   (IVotes token, TimelockController timelock, uint256 votingDelay, uint256 votingPeriod,
#    uint256 proposalThreshold, uint256 quorumFraction, uint256 initialGovernorDelay)
#
# Writes:  globals.vetoGovernorAddress
#
# Depends on: deploy_28_veto_timelock.sh (Veto Timelock must exist).

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

# Check if $1 is provided
if [ -z "$1" ]; then
  echo "${red}!!! Usage: $0 <network>${reset}"
  echo "${red}Example: $0 mainnet${reset}"
  exit 1
fi

# check if the ETHERSCAN_API_KEY is set
if [ -z "$ETHERSCAN_API_KEY" ]; then
  echo "${red}!!! Set the ETHERSCAN_API_KEY environment variable${reset}"
  exit 1
fi

# Get globals file
globals="$(dirname "$0")/globals_$1.json"
if [ ! -f $globals ]; then
  echo "${red}!!! $globals is not found${reset}"
  exit 0
fi

# Read variables using jq
contractVerification=$(jq -r '.contractVerification' $globals)
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

wveOLASAddress=$(jq -r '.wveOLASAddress' $globals)
vetoTimelockAddress=$(jq -r '.vetoTimelockAddress' $globals)
vetoVotingDelay=$(jq -r '.vetoVotingDelay' $globals)
vetoVotingPeriod=$(jq -r '.vetoVotingPeriod' $globals)
vetoProposalThreshold=$(jq -r '.vetoProposalThreshold' $globals)
vetoQuorum=$(jq -r '.vetoQuorum' $globals)
vetoGovernorDelay=$(jq -r '.vetoGovernorDelay' $globals)

# Precondition: Veto Timelock must have been deployed by deploy_28.
if [ "$vetoTimelockAddress" == "null" ] || [ -z "$vetoTimelockAddress" ]; then
  echo "${red}!!! globals.vetoTimelockAddress is unset. Run deploy_28_veto_timelock.sh $1 first.${reset}"
  exit 0
fi

mainGovernor=$(jq -r '.governorAddress' $globals)  # used later for the F1 token cross-check

# Design invariant (stable across B'-recovery — does NOT depend on live main state):
#   veto cycle (votingDelay + votingPeriod, converted to seconds) + safety margin
#   MUST FIT INSIDE the raised main Governor `governorDelay` (14 d, set by Task 2).
#
# Reason we do NOT compare to `mainGovernor.votingDelay()` live: pre-Task-2 it is 13091;
# post-Task-2 it is 72000. A live-match check would ABORT during B'-recovery and instruct
# the operator to copy the raised value into the veto — precisely the value the design
# forbids. Pinning the design constants here keeps the check correct in every state.
mainGovernorDelayTarget=1209600  # 14 d, Task-2 target for updateGovernorDelay
marginSeconds=86400              # 1 d slack (block-time jitter + Bravo cancel overhead)
# Pin (typo-catch): operator should not silently change these without also rechecking
# the invariant. Kept as today's live main values, which the design mandates for the veto.
if [ "$vetoVotingDelay" != "13091" ] || [ "$vetoVotingPeriod" != "19636" ]; then
  echo "${red}!!! globals.vetoVotingDelay/vetoVotingPeriod ($vetoVotingDelay/$vetoVotingPeriod) != design pin (13091/19636).${reset}"
  echo "${red}    Update the pin here consciously if this is intentional, and re-check the invariant below.${reset}"
  exit 0
fi
vetoCycleSeconds=$(( (vetoVotingDelay + vetoVotingPeriod) * 12 ))
if [ $(( vetoCycleSeconds + marginSeconds )) -gt $mainGovernorDelayTarget ]; then
  echo "${red}!!! Veto cycle overflow: (votingDelay+votingPeriod)*12s + margin = $((vetoCycleSeconds + marginSeconds)) s${reset}"
  echo "${red}    > mainGovernorDelayTarget ($mainGovernorDelayTarget s = 14 d). Aborting.${reset}"
  exit 0
fi

contractName="GovernorOLAS"
contractPath="contracts/$contractName.sol:$contractName"
constructorArgs="$wveOLASAddress $vetoTimelockAddress $vetoVotingDelay $vetoVotingPeriod $vetoProposalThreshold $vetoQuorum $vetoGovernorDelay"
contractArgs="$contractPath --constructor-args $constructorArgs"

# Get deployer based on the ledger flag
if [ "$useLedger" == "true" ]; then
  walletArgs="-l --mnemonic-derivation-path $derivationPath"
  deployer=$(cast wallet address $walletArgs)
else
  echo "Using PRIVATE_KEY: ${PRIVATE_KEY:0:6}..."
  walletArgs="--private-key $PRIVATE_KEY"
  deployer=$(cast wallet address $walletArgs)
fi

echo "${green}Deploying from: $deployer${reset}"
echo "RPC: $networkURL"
echo "${green}Deployment of: $contractArgs${reset}"

# Deploy Veto-Governor
execCmd="forge create --broadcast --rpc-url $networkURL$API_KEY $walletArgs $contractArgs"
deploymentOutput=$($execCmd)
vetoGovernorAddress=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

outputLength=${#vetoGovernorAddress}
if [ $outputLength != 42 ]; then
  echo "${red}!!! The contract was not deployed...${reset}"
  exit 0
fi

# Write into globals
echo "$(jq '. += {"vetoGovernorAddress":"'$vetoGovernorAddress'"}' $globals)" > $globals

# Post-deploy sanity — F1: veto.token() must equal main Governor's token().
rpcURL="$networkURL$API_KEY"
vetoToken=$(cast call --rpc-url $rpcURL $vetoGovernorAddress "token()(address)")
vetoTimelock=$(cast call --rpc-url $rpcURL $vetoGovernorAddress "timelock()(address)")
vetoGD=$(cast call --rpc-url $rpcURL $vetoGovernorAddress "governorDelay()(uint256)" | awk '{print $1}')
vetoVD=$(cast call --rpc-url $rpcURL $vetoGovernorAddress "votingDelay()(uint256)" | awk '{print $1}')
vetoVP=$(cast call --rpc-url $rpcURL $vetoGovernorAddress "votingPeriod()(uint256)" | awk '{print $1}')

echo "Post-deploy state:"
echo "  token           : $vetoToken           (must be wveOLAS $wveOLASAddress — F1)"
echo "  timelock        : $vetoTimelock        (must be Veto Timelock $vetoTimelockAddress)"
echo "  governorDelay   : $vetoGD              (must be $vetoGovernorDelay = 0 for instant cancels)"
echo "  votingDelay     : $vetoVD              (must be $vetoVotingDelay — today's value, NOT raised Layer 1)"
echo "  votingPeriod    : $vetoVP              (must be $vetoVotingPeriod)"

# Cross-check F1 against the live main Governor's token()
if [ "$mainGovernor" != "null" ] && [ -n "$mainGovernor" ]; then
  mainToken=$(cast call --rpc-url $rpcURL $mainGovernor "token()(address)")
  if [ "$(echo $mainToken | tr A-Z a-z)" != "$(echo $vetoToken | tr A-Z a-z)" ]; then
    echo "${red}!!! F1 VIOLATION: veto.token() ($vetoToken) != main.token() ($mainToken)${reset}"
    echo "${red}    Deployment failed the wveOLAS-wrapper check. Do NOT proceed to deploy_30.${reset}"
    exit 0
  fi
  echo "  F1 (token match): ${green}PASS${reset}"
fi

# Verify contract
if [ "$contractVerification" == "true" ]; then
  contractParams="$vetoGovernorAddress $contractPath --constructor-args $(cast abi-encode "constructor(address,address,uint256,uint256,uint256,uint256,uint256)" $constructorArgs)"
  echo "Verification contract params: $contractParams"

  echo "${green}Verifying contract on Etherscan...${reset}"
  forge verify-contract --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" $contractParams

  blockscoutURL=$(jq -r '.blockscoutURL' $globals)
  if [ "$blockscoutURL" != "null" ]; then
    echo "${green}Verifying contract on Blockscout...${reset}"
    forge verify-contract --verifier blockscout --verifier-url "$blockscoutURL/api" $contractParams
  fi
fi

echo "${green}Veto-Governor deployed at: $vetoGovernorAddress${reset}"
echo "${green}Next: deploy_30_wire_freeze_veto_timelock.sh $1${reset}"
