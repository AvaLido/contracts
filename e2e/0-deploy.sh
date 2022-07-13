#!/bin/sh

export RPC_URL="http://127.0.0.1:9650/ext/bc/C/rpc" # Local network
export ROLE_DEFAULT_ADMIN_PK="56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027" # Contract deployer PK

# Deploy via `forge script`
forge script src/deploy/Deploy.t.sol --sig "deploy()" --rpc-url $RPC_URL --broadcast --private-key $ROLE_DEFAULT_ADMIN_PK
