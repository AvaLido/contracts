#!/usr/bin/env bash

MPC_MANAGER_ADDRESS=$(cat MPC_MANAGER_ADDRESS)

export ROLE_DEFAULT_ADMIN="0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC" # Contract Deployer
export ROLE_DEFAULT_ADMIN_PK="56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027"

pk=$(cast call --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" $MPC_MANAGER_ADDRESS "lastGenPubKey()")
pk=0x${pk: -128}

addr=$(cast call --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" $MPC_MANAGER_ADDRESS "lastGenAddress()")
addr=0x${addr: -40}
echo "PubKey : $pk"
echo "Address: $addr"

bal=$(cast balance --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" $addr)
if [[ bal -eq 0 ]]
then

    echo "Crediting 1 ether to MPC wallet $addr as fees for MPC operations"
    ETHER=000000000000000000

    cast send --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" --from $ROLE_DEFAULT_ADMIN --private-key $ROLE_DEFAULT_ADMIN_PK \
    --value 1${ETHER} $addr
fi

bal=$(cast balance --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" $addr)

echo "Balance: $bal"
echo -n $addr > MPC_WALLET_ADDRESS