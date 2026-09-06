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
processBridgedDataArbitrumAddress=$(jq -r '.processBridgedDataArbitrumAddress' $globals)

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

# Robinhood Chain bridge mediator parameters (Arbitrum Orbit rollup, chainId 4663)
# L1: Robinhood Chain Delayed Inbox on Ethereum mainnet
robinhoodInboxAddress=$(jq -r '.robinhoodInboxAddress' $globals)
# L2: Aliased Timelock address is the bridge mediator on Robinhood Chain
robinhoodBridgeMediatorL2=$(jq -r '.robinhoodBridgeMediatorL2' $globals)
# Robinhood Chain chain Id
robinhoodChainId=4663

# Cast command
echo "${green}Casting from: $deployer${reset}"
echo "RPC: $networkURL"
echo "${green}Set bridge mediator L1 bridge params for Robinhood Chain on GuardCM${reset}"

castSendHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"
castArgs="$guardCMAddress setBridgeMediatorL1BridgeParams(address[],address[],uint256[],address[]) [$robinhoodInboxAddress] [$processBridgedDataArbitrumAddress] [$robinhoodChainId] [$robinhoodBridgeMediatorL2]"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"
