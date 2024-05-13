# Fuzzing VoteWeighting

## Prepare contracts for fuzzing
contracts/test/VoteWeightingFuzzing.sol <br>
contracts/test/EchidnaVoteWeightingAssert.sol <br> 

## Fuzzing
```sh
# Move the script to the root of the project
cp start_echidna.sh ../../../
# Move config file to the root of the project
cp echidna_assert.yaml ../../../
cd ../../../
# Run 
./start_echidna.sh
```
result overflow: [fuzzing-overflow.PNG](fuzzing-overflow.PNG) <br>
result assert: [fuzzing-assert.PNG](fuzzing-assert.PNG)
