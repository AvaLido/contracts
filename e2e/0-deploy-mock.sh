#!/bin/sh

export ROLE_DEFAULT_ADMIN="0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC" # Contract Deployer
export ROLE_DEFAULT_ADMIN_PK="56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027" # Contract deployer PK

# These exports used by integration test scripts.
export MPC_MANAGER=$(task deploy -- MpcManager | grep -i "deployed" | cut -d " " -f 3)
export MOCK_AVALIDO=$(task deploy -- MockAvaLido --constructor-args $MPC_MANAGER | grep -i "deployed" | cut -d " " -f 3)

# set AvaLido address for MpcManager
cast send --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" --from $ROLE_DEFAULT_ADMIN --private-key $ROLE_DEFAULT_ADMIN_PK -- $MPC_MANAGER "initialize()"
cast send --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" --from $ROLE_DEFAULT_ADMIN --private-key $ROLE_DEFAULT_ADMIN_PK -- $MPC_MANAGER "setAvaLidoAddress(address)" $MOCK_AVALIDO


# Print addresses for easy access
printf "MpcManager contract deployed to: $MPC_MANAGER\n"
printf "MockAvaLido contract deployed to: $MOCK_AVALIDO\n"
