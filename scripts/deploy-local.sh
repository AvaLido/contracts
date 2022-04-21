#!/bin/sh

VAL=$(task deploy -- ValidatorOracle | grep -i "deployed" | cut -d " " -f 3)
MANAGER=$(task deploy -- ValidatorManager --constructor-args $VAL | grep -i "deployed" | cut -d " " -f 3)
export AVALIDO=$(task deploy -- AvaLido --constructor-args "0x2000000000000000000000000000000000000001" "0x2000000000000000000000000000000000000002" $MANAGER "0x3000000000000000000000000000000000000001" | grep -i "deployed" | cut -d " " -f 3)
