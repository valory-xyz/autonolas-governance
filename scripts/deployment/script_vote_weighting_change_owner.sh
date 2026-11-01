#!/bin/bash
# Run only after reviewing the deployment audit and the intended Timelock address.
set -euo pipefail

fail() { echo "ERROR: $*" >&2; exit 1; }
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
[ "$#" -eq 1 ] || fail "Usage: $0 <network>"
globals="$(dirname "$0")/globals_$1.json"
[ -f "$globals" ] || fail "Globals file not found"
voteWeightingAddress=$(jq -er '.voteWeightingAddress' "$globals")
timelockAddress=$(jq -er '.timelockAddress' "$globals")
chainId=$(jq -er '.chainId' "$globals")
rpcURL=$(jq -er '.networkURL' "$globals")
for address in "$voteWeightingAddress" "$timelockAddress"; do
  [[ "$address" =~ ^0x[0-9a-fA-F]{40}$ ]] && [ "$address" != "0x0000000000000000000000000000000000000000" ] ||
    fail "VoteWeighting and Timelock must be nonzero addresses"
done

if [[ "$rpcURL" == *"alchemy.com"* ]]; then
  case "$chainId" in
    1) key=${ALCHEMY_API_KEY_MAINNET:-} ;;
    11155111) key=${ALCHEMY_API_KEY_SEPOLIA:-} ;;
    *) fail "Unsupported Alchemy chain" ;;
  esac
  [ -n "$key" ] || fail "Set the chain's Alchemy API key"
  rpcURL="$rpcURL$key"
fi
rpcChainId=$(cast chain-id --rpc-url "$rpcURL" 2>/dev/null) || fail "Cannot read RPC chain ID"
[ "$rpcChainId" = "$chainId" ] || fail "RPC chain ID does not match globals.chainId"
for address in "$voteWeightingAddress" "$timelockAddress"; do
  code=$(cast code --rpc-url "$rpcURL" "$address" 2>/dev/null) || fail "Cannot read contract code"
  [ -n "$code" ] && [ "$code" != "0x" ] || fail "No contract code at $address"
done
owner=$(cast call --rpc-url "$rpcURL" "$voteWeightingAddress" "owner()(address)" 2>/dev/null) || fail "Cannot read VoteWeighting owner"
if [ "$(lc "$owner")" = "$(lc "$timelockAddress")" ]; then
  echo "Owner already matches Timelock: $timelockAddress; no transaction sent"
  exit 0
fi

useLedger=$(jq -er '.useLedger | tostring' "$globals")
case "$useLedger" in
  true)
    derivationPath=$(jq -er '.derivationPath' "$globals")
    walletArgs=(-l --mnemonic-derivation-path "$derivationPath") ;;
  false)
    [ -n "${PRIVATE_KEY:-}" ] || fail "Set PRIVATE_KEY or use Ledger"
    walletArgs=(--private-key "$PRIVATE_KEY") ;;
  *) fail "useLedger must be true or false" ;;
esac
signer=$(cast wallet address "${walletArgs[@]}" 2>/dev/null) || fail "Cannot read signer address"
[ "$(lc "$owner")" = "$(lc "$signer")" ] || fail "Signer is not the current VoteWeighting owner"
echo "VoteWeighting: $voteWeightingAddress; current owner: $owner; intended owner: $timelockAddress"
receipt=$(cast send --rpc-url "$rpcURL" "${walletArgs[@]}" --confirmations 1 --json \
  "$voteWeightingAddress" "changeOwner(address)" "$timelockAddress" 2>/dev/null) || fail "Ownership transaction failed; check its on-chain status before retrying"
printf '%s' "$receipt" | jq -e '.status == "0x1" or .status == 1' >/dev/null || fail "Ownership receipt does not report success"
echo "Ownership transaction: $(printf '%s' "$receipt" | jq -er '.transactionHash')"
owner=$(cast call --rpc-url "$rpcURL" "$voteWeightingAddress" "owner()(address)" 2>/dev/null) || fail "Cannot verify owner after transaction"
[ "$(lc "$owner")" = "$(lc "$timelockAddress")" ] || fail "Owner mismatch after transaction: expected=$timelockAddress, observed=$owner"
echo "Owner verified: $owner"
