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
processBridgedDataOptimismAddress=$(jq -r '.processBridgedDataOptimismAddress' $globals)

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

# Optimism-type bridge mediator parameters (Optimism, Base, Mode, Celo all use L1CrossDomainMessenger)
# L1 bridge mediators on Ethereum mainnet
optimismL1CrossDomainMessenger=$(jq -r '.optimismL1CrossDomainMessengerAddress' $globals)
baseL1CrossDomainMessenger=$(jq -r '.baseL1CrossDomainMessengerAddress' $globals)
modeL1CrossDomainMessenger=$(jq -r '.modeL1CrossDomainMessengerAddress' $globals)
celoL1CrossDomainMessenger=$(jq -r '.celoL1CrossDomainMessengerAddress' $globals)

# L2 bridge mediators (OptimismMessenger on each chain)
optimismMessengerL2=$(jq -r '.optimismMessengerL2Address' $globals)
baseMessengerL2=$(jq -r '.baseMessengerL2Address' $globals)
modeMessengerL2=$(jq -r '.modeMessengerL2Address' $globals)
celoMessengerL2=$(jq -r '.celoMessengerL2Address' $globals)

# Chain Ids
optimismChainId=10
baseChainId=8453
modeChainId=34443
celoChainId=42220

# Cast command
echo "${green}Casting from: $deployer${reset}"
echo "RPC: $networkURL"
echo "${green}Set bridge mediator L1 bridge params for Optimism/Base/Mode/Celo on GuardCM${reset}"

castSendHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"
castArgs="$guardCMAddress setBridgeMediatorL1BridgeParams(address[],address[],uint256[],address[]) [$optimismL1CrossDomainMessenger,$baseL1CrossDomainMessenger,$modeL1CrossDomainMessenger,$celoL1CrossDomainMessenger] [$processBridgedDataOptimismAddress,$processBridgedDataOptimismAddress,$processBridgedDataOptimismAddress,$processBridgedDataOptimismAddress] [$optimismChainId,$baseChainId,$modeChainId,$celoChainId] [$optimismMessengerL2,$baseMessengerL2,$modeMessengerL2,$celoMessengerL2]"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"
