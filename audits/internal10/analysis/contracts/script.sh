#!/bin/bash

    slither_options=("call-graph" "constructor-calls" "contract-summary" "data-dependency" "function-summary"
        "human-summary" "inheritance" "inheritance-graph"	"modifiers"	"require"	"variable-order" "vars-and-auth")
    echo -e "\nRunning slither routines ..."
    for so in "${slither_options[@]}"; do
        echo -e "\t$so"
        slither . --print ${so} &> "slither_$so.txt"
    done
    echo -e "\tfull report"
    slither . &> "slither_full.txt"

    # moving generated .dot files to the audit folder
    count=`ls -1 *.dot 2>/dev/null | wc -l`
    echo -e "\tgenerated $count .dot files"
    for _filename in *.dot; do
        filename="${_filename%.*}"
        cat $_filename | dot -Tpng > slither_$filename.png
    done
    rm *.dot
