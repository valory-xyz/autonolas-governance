#!/bin/bash

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

# Get globals file
globals="$(dirname "$0")/globals_$1.json"
if [ ! -f $globals ]; then
  echo "${red}!!! $globals is not found${reset}"
  exit 0
fi

# Read variables using jq
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)

guardCMAddress=$(jq -r '.guardCMAddress' $globals)
processBridgedDataGnosisAddress=$(jq -r '.processBridgedDataGnosisAddress' $globals)

# Check for Alchemy keys on ETH, Polygon mainnets and testnets
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

# Get deployer based on the ledger flag
if [ "$useLedger" == "true" ]; then
  walletArgs="-l --mnemonic-derivation-path $derivationPath"
  deployer=$(cast wallet address $walletArgs)
else
  echo "Using PRIVATE_KEY: ${PRIVATE_KEY:0:6}..."
  walletArgs="--private-key $PRIVATE_KEY"
  deployer=$(cast wallet address $walletArgs)
fi

# Gnosis bridge mediator parameters
# L1: AMBContractProxyForeign on Ethereum mainnet
AMBContractProxyForeignAddress=$(jq -r '.AMBContractProxyForeignAddress' $globals)
# L2: HomeMediator on Gnosis chain
gnosisBridgeMediatorL2=$(jq -r '.gnosisBridgeMediatorL2' $globals)
# Gnosis chain Id
gnosisChainId=100

# Cast command
echo "${green}Casting from: $deployer${reset}"
echo "RPC: $networkURL"
echo "${green}Set bridge mediator L1 bridge params for Gnosis on GuardCM${reset}"

castSendHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"
castArgs="$guardCMAddress setBridgeMediatorL1BridgeParams(address[],address[],uint256[],address[]) [$AMBContractProxyForeignAddress] [$processBridgedDataGnosisAddress] [$gnosisChainId] [$gnosisBridgeMediatorL2]"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"
