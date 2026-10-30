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
# PREREQUISITE — deploy and audit the new Dispenser implementation/proxy in tokenomics first.
# Copy tokenomics globals.dispenserProxyAddress to governance globals.dispenserAddress, and
# tokenomics globals.dispenserAddress to governance globals.dispenserImplementationAddress.
# The latter is the expected reviewed implementation for the proxy-slot check, not a ctor argument.
# This flow requires the new proxy even before the old system is replaced. A wrong immutable
# binding can only be fixed by redeploying VoteWeighting.
# After deployment, copy voteWeightingAddress back to tokenomics globals for later manager wiring.
# Cross-repo runbook:
# https://github.com/valory-xyz/autonolas-tokenomics/blob/main/docs/dispenser_migration_runbook_public.md
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

# Validate both the constructor target and the expected implementation before any broadcast.
dispenserAddress=$(jq -r '.dispenserAddress' "$globals")
dispenserImplementationAddress=$(jq -r '.dispenserImplementationAddress' "$globals")
for address in "$veOLASAddress" "$dispenserAddress" "$dispenserImplementationAddress"; do
  if [[ ! "$address" =~ ^0x[0-9a-fA-F]{40}$ ]] || [[ "$address" == "0x0000000000000000000000000000000000000000" ]]; then
    echo "${red}!!! veOLASAddress, dispenserAddress and dispenserImplementationAddress must be nonzero addresses${reset}"
    exit 1
  fi
done

rpcURL="$networkURL$API_KEY"
if ! rpcChainId=$(cast chain-id --rpc-url "$rpcURL" 2>/dev/null) || [ "$rpcChainId" != "$chainId" ]; then
  echo "${red}!!! RPC chain ID does not match globals.chainId${reset}"
  exit 1
fi

# A nonzero owner alone does not distinguish the proxy from an initialized implementation.
# Read the DispenserProxy slot (keccak256("PROXY_DISPENSER")) and compare its full stored word.
dispenserSlot=0x8bd249c73459f2c50400ebdc57436101fc7d9a76908baf1ba5be362b47b48f83
expectedSlot="0x000000000000000000000000${dispenserImplementationAddress:2}"
if ! actualSlot=$(cast storage --rpc-url "$rpcURL" "$dispenserAddress" "$dispenserSlot" 2>/dev/null) || \
   [ "$(echo "$actualSlot" | tr '[:upper:]' '[:lower:]')" != "$(echo "$expectedSlot" | tr '[:upper:]' '[:lower:]')" ]; then
  echo "${red}!!! Dispenser proxy implementation mismatch: expected=$expectedSlot, observed=${actualSlot:-unavailable}${reset}"
  exit 1
fi
if ! implementationCode=$(cast code --rpc-url "$rpcURL" "$dispenserImplementationAddress" 2>/dev/null) || \
   [ -z "$implementationCode" ] || [ "$implementationCode" == "0x" ]; then
  echo "${red}!!! Expected Dispenser implementation has no readable contract code${reset}"
  exit 1
fi

dispenserCode=$(cast code --rpc-url "$rpcURL" "$dispenserAddress") || exit 1
if [ "$dispenserCode" == "0x" ] || [ -z "$dispenserCode" ]; then
  echo "${red}!!! dispenserAddress $dispenserAddress has no contract code on chain $chainId${reset}"
  exit 1
fi

dispenserOwner=$(cast call --rpc-url $rpcURL $dispenserAddress "owner()(address)" 2>/dev/null)
if [ -z "$dispenserOwner" ] || [ "$dispenserOwner" == "0x0000000000000000000000000000000000000000" ]; then
  echo "${red}!!! dispenserAddress $dispenserAddress reads owner() == 0 (or has no owner())${reset}"
  echo "${red}    The Dispenser proxy must be initialized before deploying VoteWeighting.${reset}"
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
