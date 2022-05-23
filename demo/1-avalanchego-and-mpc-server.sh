#!/usr/bin/env bash

mkdir -p logs

pkill -f avalanchego
pkill -f mpc-server

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Start avalanchego
avalanchego --network-id=local --staking-enabled=false --snow-sample-size=1 --snow-quorum-size=1 --genesis $SCRIPT_DIR/../network/genesis.json --network-id 1337 \
> logs/node.log 2>&1 &

# Start mpc-server
mpc-server > logs/mpc-server.log 2>&1 &