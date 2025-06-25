#!/bin/bash

# network contract_name contract_address
# using: ./scripts/audit_chains/audit_short.sh etherscan RegistriesManager 0x9eC9156dEF5C613B2a7D4c46C383F9B58DfcD6fE

if ! command -v ethereum-sources-downloader &> /dev/null
then
    # https://github.com/SergeKireev/ethereum-sources-downloader
    echo "ethereum-sources-downloader could not be found"
    npm i ethereum-sources-downloader
fi

outDirName="out_static_audit"

# clean before
if [ -d "$outDirName" ]; then
  rm -rf $outDirName
fi

node_modules/ethereum-sources-downloader/dist/index.js $1 $3 $outDirName -a v2 -k $ETHERSCAN_API_KEY 2>&1 > /dev/null
# ignore only in dir
r=$(diff -r $outDirName/$2/contracts/ contracts/ | grep -v Only)
#clear after
rm -rf $outDirName
if [ -z "$r" ]
then
      echo "OK. $2 ($3) on $1 eq contracts"
      EXIT_CODE=0 
else
      >&2 echo "FAILED: $2 ($3) on $1 NOT eq contracts"
      >&2 echo $r
      EXIT_CODE=1
fi

exit $EXIT_CODE