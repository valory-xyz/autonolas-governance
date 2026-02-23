#!/bin/bash

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

# Get globals file
globals="$(dirname "$0")/globals_mainnet.json"
if [ ! -f $globals ]; then
  echo "${red}!!! $globals is not found${reset}"
  exit 0
fi

# Read variables using jq
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
networkURL="https://forno.celo.org"

l2Factory="0x4200000000000000000000000000000000000012"
olasAddress=$(jq -r '.olasAddress' $globals)
name="Autonolas"
symbol="OLAS"

# Get deployer based on the ledger flag
if [ "$useLedger" == "true" ]; then
  walletArgs="-l --mnemonic-derivation-path $derivationPath"
  deployer=$(cast wallet address $walletArgs)
else
  echo "Using PRIVATE_KEY: ${PRIVATE_KEY:0:6}..."
  walletArgs="--private-key $PRIVATE_KEY"
  deployer=$(cast wallet address $walletArgs)
fi

# Cast message
echo "Casting from: $deployer"

castSendHeader="cast send --rpc-url $networkURL $walletArgs"

echo "${green}Create L2 OP chain OLAS${reset}"
castArgs="$l2Factory createOptimismMintableERC20(address,string,string) $olasAddress $name $symbol"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"

