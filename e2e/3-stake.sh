#!/bin/sh

AVALIDO_ADDRESS=$1

if [ -z $AVALIDO_ADDRESS ]
then
    echo "Please supply AvaLido address."
    exit 1
fi

export RPC_URL="http://127.0.0.1:9650/ext/bc/C/rpc" # Local network
export ROLE_DEFAULT_ADMIN="0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC" # Contract Deployer
export ROLE_DEFAULT_ADMIN_PK="56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027" # Contract deployer PK

cast send --gas-limit 900000 --rpc-url $RPC_URL --from $ROLE_DEFAULT_ADMIN --private-key $ROLE_DEFAULT_ADMIN_PK -- $AVALIDO_ADDRESS "initiateStake()"
