#!/usr/bin/bash
echo "Deploying chaincode..."
./network.sh deployCC -ccn fabcar -ccp ../chaincode/fabcar/go -ccl go
