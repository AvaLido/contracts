#!/usr/bin/env bash

AVALIDO_ADDRESS=$(cat AVALIDO_ADDRESS)

export ROLE_DEFAULT_ADMIN="0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC" # Contract Deployer
export ROLE_DEFAULT_ADMIN_PK="56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027"

cast send --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" --value 1 --from $ROLE_DEFAULT_ADMIN --private-key $ROLE_DEFAULT_ADMIN_PK \
--gas 900000 \
$AVALIDO_ADDRESS "initiateStake()"
