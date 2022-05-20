#!/bin/sh

export ROLE_DEFAULT_ADMIN="0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC" # Contract Deployer
export ROLE_DEFAULT_ADMIN_PK="56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027" # Contract deployer PK
export ROLE_ORACLE_MANAGER=$ROLE_DEFAULT_ADMIN
export ROLE_ORACLE_MANAGER_PK=$ROLE_DEFAULT_ADMIN_PK
export VALIDATOR_WHITELIST=["NodeID-P7oB2McjBGgW2NXXWVYjV8JEDFoW9xDE5","NodeID-GWPcbFJZFfZreETSoWjPimr846mXEKCtu","NodeID-NFBbbJ4qCmNaCzeW7sxErhvWqvEQMnYcN"]
export ORACLE_WHITELIST=["0x03C1196617387899390d3a98fdBdfD407121BB67","0x6C58f6E7DB68D9F75F2E417aCbB67e7Dd4e413bf","0xa7bB9405eAF98f36e2683Ba7F36828e260BD0018","0xE339767906891bEE026285803DA8d8F2f346842C","0x0309a747a34befD1625b5dcae0B00625FAa30460"]

# These exports used by integration test scripts.
export MPC_MANAGER=$(task deploy -- MpcManager | grep -i "deployed" | cut -d " " -f 3)
export ORACLE_MANAGER=$(task deploy -- OracleManager --constructor-args $ROLE_ORACLE_MANAGER $VALIDATOR_WHITELIST $ORACLE_WHITELIST | grep -i "deployed" | cut -d " " -f 3)
export ORACLE=$(task deploy -- Oracle --constructor-args $ROLE_ORACLE_MANAGER $ORACLE_MANAGER | grep -i "deployed" | cut -d " " -f 3)
export VALIDATOR_SELECTOR=$(task deploy -- ValidatorSelector --constructor-args $ORACLE | grep -i "deployed" | cut -d " " -f 3)
export AVALIDO=$(task deploy -- AvaLido --constructor-args "0x2000000000000000000000000000000000000001" "0x2000000000000000000000000000000000000002" $VALIDATOR_SELECTOR $MPC_MANAGER | grep -i "deployed" | cut -d " " -f 3)

# set AvaLido address for MpcManager
cast send --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" --from $ROLE_DEFAULT_ADMIN --private-key $ROLE_DEFAULT_ADMIN_PK -- $MPC_MANAGER "setAvaLidoAddress(address)" $AVALIDO

# set oracle address from oraclemanager
# task call -- $ORACLE_MANAGER "setOracleAddress(address)" $ORACLE --from $ROLE_ORACLE_MANAGER --private-key $ROLE_ORACLE_MANAGER_PK
cast send --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" --from $ROLE_ORACLE_MANAGER --private-key $ROLE_ORACLE_MANAGER_PK -- $ORACLE_MANAGER "setOracleAddress(address)" $ORACLE

# Print addresses for easy access
printf "MpcManager contract deployed to: $MPC_MANAGER\n"
printf "OracleManager contract deployed to: $ORACLE_MANAGER\n"
printf "Oracle contract deployed to: $ORACLE\n"
printf "ValidatorSelector contract deployed to: $VALIDATOR_SELECTOR\n"
printf "AvaLido contract deployed to: $AVALIDO\n"