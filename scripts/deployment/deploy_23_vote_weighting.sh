#!/bin/bash

# Deploy VoteWeighting — the Curve-style gauge controller for nominee vote allocation.
#
# VoteWeighting ctor: (address _ve, address _dispenser)
#   - _ve         = globals.veOLASAddress   (veOLAS the contract binds to; required, non-zero)
#   - _dispenser  = globals.dispenserAddress (immutable; set once and never changed).
#                   The Dispenser must therefore be deployed BEFORE VoteWeighting. The contract
#                   itself accepts a zero dispenser to run standalone, but that is NOT this
#                   deployment's case: for the tokenomics wiring a zero here would permanently
#                   brick the Dispenser link, so a missing/zero dispenserAddress is a hard error.
#
# PREREQUISITE — refresh globals.dispenserAddress before every run:
#   globals_<network>.json has no dispenserAddress key on purpose. Before deploying, add it and set
#   it to the CURRENT LIVE Dispenser address from the autonolas-tokenomics repo's
#   globals_<network>.json. WHICH KEY holds that address depends on whether the proxied-Dispenser
#   migration has happened yet:
#     - BEFORE the migration (today): the live Dispenser is the plain `dispenserAddress` key.
#     - AFTER the migration (once deploy_07b_dispenser_proxy.sh has run there): the live Dispenser
#       is `dispenserProxyAddress`, and from that point `dispenserAddress` in that repo means the
#       Dispenser IMPLEMENTATION behind the proxy — NEVER copy that one here.
#   Whenever new Dispenser contracts are deployed there this value changes and MUST be re-copied
#   before VoteWeighting is deployed: VoteWeighting binds the dispenser immutably, so a wrong or
#   stale address can only be fixed by redeploying VoteWeighting.
#   Cross-repo runbook (the same handoff from the tokenomics side, step 9):
#   https://github.com/valory-xyz/autonolas-tokenomics/blob/main/docs/dispenser_migration_runbook_public.md
#
# Writes:  globals.voteWeightingAddress  (overwrites any previous VoteWeighting address)

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

veOLASAddress=$(jq -r '.veOLASAddress' $globals)
if [ "$veOLASAddress" == "null" ] || [ -z "$veOLASAddress" ]; then
  echo "${red}!!! veOLASAddress is not set in $globals${reset}"
  exit 0
fi

# Dispenser is immutable and must be a real, non-zero address for this deployment. The zero
# address is a valid ctor input for a standalone VoteWeighting, but here it would silently
# brick the Dispenser wiring with no recovery but redeployment — so refuse it loudly.
dispenserAddress=$(jq -r '.dispenserAddress' $globals)
if [ "$dispenserAddress" == "null" ] || [ -z "$dispenserAddress" ] || [ "$dispenserAddress" == "0x0000000000000000000000000000000000000000" ]; then
  echo "${red}!!! dispenserAddress is not set (or is the zero address) in $globals${reset}"
  echo "${red}    VoteWeighting binds the dispenser immutably; refusing to deploy with no dispenser.${reset}"
  echo "${red}    Copy the LIVE Dispenser address from the autonolas-tokenomics globals_$1.json into${reset}"
  echo "${red}    dispenserAddress here: key 'dispenserAddress' before the proxied-Dispenser migration,${reset}"
  echo "${red}    key 'dispenserProxyAddress' after it (then their 'dispenserAddress' is the${reset}"
  echo "${red}    implementation — never copy that). Re-check after every new Dispenser deployment.${reset}"
  exit 1
fi

rpcURL="$networkURL$API_KEY"

# Pre-flight on the dispenser BEFORE deploying: the post-deploy asserts below can only report a
# wrong dispenser, they cannot undo it (immutable), so the cheap checks that can prevent the
# mistake belong here.
#   1. It must be a contract at all — an EOA / empty address would brick the link silently.
#   2. owner() must be non-zero. This is what separates a live Dispenser from the Dispenser
#      IMPLEMENTATION address: the implementation's constructor sets immutables only, its owner
#      lives in initialize() which the DispenserProxy constructor delegatecalls — so a bare
#      implementation reads owner() == 0, while both the pre-migration live Dispenser and the
#      post-migration DispenserProxy read a real owner.
# Note: voteWeighting() is NOT usable as a check here — a freshly deployed DispenserProxy is
# initialized with voteWeighting == 0 by design (this contract does not exist yet and binds the
# proxy), so it is printed for information only.
dispenserCode=$(cast code --rpc-url $rpcURL $dispenserAddress)
if [ "$dispenserCode" == "0x" ] || [ -z "$dispenserCode" ]; then
  echo "${red}!!! dispenserAddress $dispenserAddress has no contract code on chain $chainId${reset}"
  exit 1
fi

dispenserOwner=$(cast call --rpc-url $rpcURL $dispenserAddress "owner()(address)" 2>/dev/null)
if [ -z "$dispenserOwner" ] || [ "$dispenserOwner" == "0x0000000000000000000000000000000000000000" ]; then
  echo "${red}!!! dispenserAddress $dispenserAddress reads owner() == 0 (or has no owner())${reset}"
  echo "${red}    This looks like a Dispenser IMPLEMENTATION rather than the live Dispenser /${reset}"
  echo "${red}    DispenserProxy. Binding it here is immutable and unrecoverable — refusing to deploy.${reset}"
  exit 1
fi

dispenserVW=$(cast call --rpc-url $rpcURL $dispenserAddress "voteWeighting()(address)" 2>/dev/null)
echo "${green}Pre-flight dispenser $dispenserAddress: owner() = $dispenserOwner${reset}"
echo "  voteWeighting() = ${dispenserVW:-<no such getter>}  (zero is expected on a freshly deployed proxy)"

contractName="VoteWeighting"
contractPath="contracts/$contractName.sol:$contractName"
constructorArgs="$veOLASAddress $dispenserAddress"
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

# Deploy the contract and capture the address
execCmd="forge create --broadcast --rpc-url $networkURL$API_KEY $walletArgs $contractArgs"
deploymentOutput=$($execCmd)
voteWeightingAddress=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#voteWeightingAddress}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "${red}!!! The contract was not deployed...${reset}"
  exit 0
fi

# Write new deployed contract back into JSON
echo "$(jq '. += {"voteWeightingAddress":"'$voteWeightingAddress'"}' $globals)" > $globals

# Post-deploy sanity: the immutable ve / dispenser slots must equal the constructor args
veGetter=$(cast call --rpc-url $rpcURL $voteWeightingAddress "ve()(address)")
dispenserGetter=$(cast call --rpc-url $rpcURL $voteWeightingAddress "dispenser()(address)")
ownerGetter=$(cast call --rpc-url $rpcURL $voteWeightingAddress "owner()(address)")

echo "Post-deploy state:"
echo "  ve        : $veGetter        (must be $veOLASAddress)"
echo "  dispenser : $dispenserGetter (must be $dispenserAddress)"
echo "  owner     : $ownerGetter     (must be the deployer $deployer)"

# Hard assertions: the immutable ve / dispenser slots cannot be fixed post-deploy, so a
# mismatch must fail the run (case-insensitive compare — cast returns checksummed addresses)
lc() { echo "$1" | tr '[:upper:]' '[:lower:]'; }
if [ "$(lc "$veGetter")" != "$(lc "$veOLASAddress")" ]; then
  echo "${red}!!! ve() mismatch: got $veGetter, expected $veOLASAddress${reset}"
  exit 1
fi
if [ "$(lc "$dispenserGetter")" != "$(lc "$dispenserAddress")" ]; then
  echo "${red}!!! dispenser() mismatch: got $dispenserGetter, expected $dispenserAddress${reset}"
  exit 1
fi
if [ "$(lc "$ownerGetter")" != "$(lc "$deployer")" ]; then
  echo "${red}!!! owner() mismatch: got $ownerGetter, expected $deployer${reset}"
  exit 1
fi
echo "${green}Post-deploy sanity checks passed${reset}"

# Verify contract on Etherscan / Blockscout
if [ "$contractVerification" == "true" ]; then
  contractParams="$voteWeightingAddress $contractPath --constructor-args $(cast abi-encode "constructor(address,address)" $constructorArgs)"
  echo "Verification contract params: $contractParams"

  echo "${green}Verifying contract on Etherscan...${reset}"
  forge verify-contract --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" $contractParams

  blockscoutURL=$(jq -r '.blockscoutURL' $globals)
  if [ "$blockscoutURL" != "null" ]; then
    echo "${green}Verifying contract on Blockscout...${reset}"
    forge verify-contract --verifier blockscout --verifier-url "$blockscoutURL/api" $contractParams
  fi
fi

echo "${green}$contractName deployed at: $voteWeightingAddress${reset}"
