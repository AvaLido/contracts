#!/usr/bin/env bash


export ROLE_DEFAULT_ADMIN="0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC" # Contract Deployer
export ROLE_DEFAULT_ADMIN_PK="56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027" # Contract deployer PK

AVALIDO_ADDRESS=$(cat AVALIDO_ADDRESS)
MPC_MANAGER_ADDRESS=$(cat MPC_MANAGER_ADDRESS)
MPC_WALLET_ADDRESS=$(cat MPC_WALLET_ADDRESS)

uBal=$(cast balance --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" $ROLE_DEFAULT_ADMIN )
aBal=$(cast balance --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" $AVALIDO_ADDRESS )
mBal=$(cast balance --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" $MPC_MANAGER_ADDRESS )
wBal=$(cast balance --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" $MPC_WALLET_ADDRESS )

stakes=$(curl --silent --location --request POST 'http://localhost:9650/ext/bc/P' \
--header 'Content-Type: application/json' \
--data-raw '{
    "jsonrpc": "2.0",
    "method": "platform.getCurrentValidators",
    "params": {
        "subnetID":null,
        "nodeIDs":[]
    },
    "id": 1
}' | jq ".result.validators | first | .delegators[].stakeAmount")

echo "User Balance       : $uBal"
echo "AvaLido Balance    : $aBal"
echo "Mpc Manager Balance: $mBal"
echo "Mpc Wallet Balance : $wBal"
echo -e "Stakes:\n$stakes"