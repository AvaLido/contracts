#!/bin/sh

# These exports used by integration test scripts.
export VALIDATOR_ORACLE=$(task deploy -- ValidatorOracle | grep -i "deployed" | cut -d " " -f 3)
export VALIDATOR_MANAGER=$(task deploy -- ValidatorManager --constructor-args $VALIDATOR_ORACLE | grep -i "deployed" | cut -d " " -f 3)
export AVALIDO=$(task deploy -- AvaLido --constructor-args "0x2000000000000000000000000000000000000001" "0x2000000000000000000000000000000000000002" $VALIDATOR_MANAGER "0x3000000000000000000000000000000000000001" | grep -i "deployed" | cut -d " " -f 3)
