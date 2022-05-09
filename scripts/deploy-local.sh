#!/bin/sh

export ROLE_ORACLE_MANAGER="0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC" # Contract Deployer
export VALIDATOR_WHITELIST=["NodeID-P7oB2McjBGgW2NXXWVYjV8JEDFoW9xDE5","NodeID-GWPcbFJZFfZreETSoWjPimr846mXEKCtu","NodeID-NFBbbJ4qCmNaCzeW7sxErhvWqvEQMnYcN"]
export ORACLE_WHITELIST=["0x03C1196617387899390d3a98fdBdfD407121BB67","0x6C58f6E7DB68D9F75F2E417aCbB67e7Dd4e413bf","0xa7bB9405eAF98f36e2683Ba7F36828e260BD0018"]

# These exports used by integration test scripts.
export ORACLE_MANAGER=$(task deploy -- OracleManager --constructor-args $ROLE_ORACLE_MANAGER $VALIDATOR_WHITELIST $ORACLE_WHITELIST | grep -i "deployed" | cut -d " " -f 3)
export ORACLE==$(task deploy -- Oracle --constructor-args $ORACLE_MANAGER | grep -i "deployed" | cut -d " " -f 3)
export VALIDATOR_ORACLE=$(task deploy -- ValidatorOracle | grep -i "deployed" | cut -d " " -f 3)
export VALIDATOR_MANAGER=$(task deploy -- ValidatorManager --constructor-args $VALIDATOR_ORACLE | grep -i "deployed" | cut -d " " -f 3)
export AVALIDO=$(task deploy -- AvaLido --constructor-args "0x2000000000000000000000000000000000000001" "0x2000000000000000000000000000000000000002" $VALIDATOR_MANAGER "0x3000000000000000000000000000000000000001" | grep -i "deployed" | cut -d " " -f 3)

# Print addresses for easy access
printf "OracleManager contract deployed to: $ORACLE_MANAGER\n"
printf "Oracle contract deployed to: $ORACLE\n"
printf "ValidatorOracle contract deployed to: $VALIDATOR_ORACLE\n"
printf "ValidatorManager contract deployed to: $VALIDATOR_MANAGER\n"
printf "AvaLido contract deployed to: $AVALIDO\n"