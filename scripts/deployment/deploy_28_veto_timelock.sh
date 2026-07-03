#!/bin/bash

# Deploy Veto Timelock — the cancel-only timelock behind the Veto-Governor stack.
#
# Veto Timelock is a stock `contracts/Timelock.sol` (OZ v4.8.3 TimelockController subclass) with:
#   - minDelay = 0 (from globals.vetoMinDelay)
#   - proposers = []           (no roles granted at construction — the Veto-Governor doesn't
#                               exist yet; PROPOSER/CANCELLER/EXECUTOR are granted by
#                               deploy_30_wire_freeze_veto_timelock.sh, AFTER the Veto-Governor is
#                               deployed in deploy_29_veto_governor.sh)
#   - executors = []
#   - admin (msg.sender): the deployer, held only until the freeze in deploy_30. This is the
#                         iterative-wiring variant that closes the deploy-order constraint (the address-prediction
#                         variant is impossible without CREATE2 pre-computation).
#
# After deploy: deployer holds TIMELOCK_ADMIN_ROLE on Veto Timelock; no other roles exist.
# The role-freeze happens in deploy_30; do not release the deployer key between these steps.
#
# Writes:  globals.vetoTimelockAddress

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

# Check for Alchemy keys on ETH mainnet + Sepolia
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

vetoMinDelay=$(jq -r '.vetoMinDelay' $globals)

contractName="Timelock"
contractPath="contracts/$contractName.sol:$contractName"
# Timelock ctor: (uint256 minDelay, address[] proposers, address[] executors) — admin = msg.sender.
# Empty arrays are passed literally so no roles are granted at construction time.
constructorArgs="$vetoMinDelay [] []"
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

# Deployment message
echo "${green}Deploying from: $deployer${reset}"
echo "RPC: $networkURL"
echo "${green}Deployment of: $contractArgs${reset}"

# Deploy Veto Timelock and capture the address
execCmd="forge create --broadcast --rpc-url $networkURL$API_KEY $walletArgs $contractArgs"
deploymentOutput=$($execCmd)
vetoTimelockAddress=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#vetoTimelockAddress}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "${red}!!! The contract was not deployed...${reset}"
  exit 0
fi

# Write new deployed contract back into JSON
echo "$(jq '. += {"vetoTimelockAddress":"'$vetoTimelockAddress'"}' $globals)" > $globals

# Post-deploy sanity: deployer + TimelockB hold TIMELOCK_ADMIN_ROLE; no other roles set.
adminRole=$(cast keccak "TIMELOCK_ADMIN_ROLE")
proposerRole=$(cast keccak "PROPOSER_ROLE")
executorRole=$(cast keccak "EXECUTOR_ROLE")
cancellerRole=$(cast keccak "CANCELLER_ROLE")
rpcURL="$networkURL$API_KEY"

deployerHoldsAdmin=$(cast call --rpc-url $rpcURL $vetoTimelockAddress "hasRole(bytes32,address)(bool)" $adminRole $deployer)
selfAdmin=$(cast call --rpc-url $rpcURL $vetoTimelockAddress "hasRole(bytes32,address)(bool)" $adminRole $vetoTimelockAddress)
minDelayGetter=$(cast call --rpc-url $rpcURL $vetoTimelockAddress "getMinDelay()(uint256)" | awk '{print $1}')

echo "Post-deploy state:"
echo "  deployer holds ADMIN     : $deployerHoldsAdmin  (must be true)"
echo "  vetoTimelock self-admin  : $selfAdmin           (must be true; will be revoked in deploy_30)"
echo "  minDelay                 : $minDelayGetter      (must be $vetoMinDelay)"
# Note: no role-member enumeration — TimelockController inherits AccessControl (not
# AccessControlEnumerable), so getRoleMemberCount is not available. The empty
# proposers[]/executors[] arrays passed to the constructor guarantee no members exist
# for PROPOSER/CANCELLER/EXECUTOR at this stage.

# Verify contract on Etherscan / Blockscout
if [ "$contractVerification" == "true" ]; then
  # Ctor is (uint256, address[], address[]) — encode with cast.
  encodedArgs=$(cast abi-encode "constructor(uint256,address[],address[])" $vetoMinDelay "[]" "[]")
  contractParams="$vetoTimelockAddress $contractPath --constructor-args $encodedArgs"

  echo "${green}Verifying contract on Etherscan...${reset}"
  forge verify-contract --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" $contractParams

  blockscoutURL=$(jq -r '.blockscoutURL' $globals)
  if [ "$blockscoutURL" != "null" ]; then
    echo "${green}Verifying contract on Blockscout...${reset}"
    forge verify-contract --verifier blockscout --verifier-url "$blockscoutURL/api" $contractParams
  fi
fi

echo "${green}Veto Timelock deployed at: $vetoTimelockAddress${reset}"
echo "${green}Next: deploy_29_veto_governor.sh $1${reset}"
