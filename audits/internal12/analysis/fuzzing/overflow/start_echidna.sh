#!/bin/bash

rm -rf corpusEchidna/
echidna contracts/test/EchidnaVoteWeightingAssert.sol --contract EchidnaVoteWeightingAssert --config echidna_overflow.yaml 
