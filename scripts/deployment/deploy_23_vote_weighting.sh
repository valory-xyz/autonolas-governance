#!/bin/bash

# Deploy VoteWeighting — the Curve-style gauge controller for nominee vote allocation.
#
# VoteWeighting ctor: (address _ve, address _dispenser)
#   - _ve         = globals.veOLASAddress   (veOLAS the contract binds to; required, non-zero)
#   - _dispenser  = globals.dispenserAddress (immutable; set once and never changed).
#                   The Dispenser must therefore be deployed BEFORE VoteWeighting. A zero address
#                   is allowed for a general-purpose deployment with no dispenser; when the globals
#                   key is absent it defaults to the zero address here.
#
# Writes:  globals.voteWeightingAddress

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

# Dispenser is immutable; default to the zero address when the globals key is absent
dispenserAddress=$(jq -r '.dispenserAddress' $globals)
if [ "$dispenserAddress" == "null" ] || [ -z "$dispenserAddress" ]; then
  dispenserAddress="0x0000000000000000000000000000000000000000"
  echo "${green}dispenserAddress not set — deploying with the zero address (no dispenser)${reset}"
fi

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
rpcURL="$networkURL$API_KEY"
veGetter=$(cast call --rpc-url $rpcURL $voteWeightingAddress "ve()(address)")
dispenserGetter=$(cast call --rpc-url $rpcURL $voteWeightingAddress "dispenser()(address)")
ownerGetter=$(cast call --rpc-url $rpcURL $voteWeightingAddress "owner()(address)")

echo "Post-deploy state:"
echo "  ve        : $veGetter        (must be $veOLASAddress)"
echo "  dispenser : $dispenserGetter (must be $dispenserAddress)"
echo "  owner     : $ownerGetter     (must be the deployer $deployer)"

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
