#!/usr/bin/env sh
##################################################################################################
# This script is used for testing smart contracts only. When AvaLido calls MpcManager, we expect #
# a key has already been generated. This script initialize the MpcManager with a fake key, so it #
# shouldn't be used in production.                                                               #
##################################################################################################

MPC_MANAGER_ADDRESS=$1

if [ -z $MPC_MANAGER_ADDRESS ]
then
    echo "Please supply MPC Manager address."
    exit 1
fi

export ROLE_DEFAULT_ADMIN="0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC" # Contract Deployer
export ROLE_DEFAULT_ADMIN_PK="56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027"
export MPC_PLAYER_PUBKEY=["0xc20e0c088bb20027a77b1d23ad75058df5349c7a2bfafff7516c44c6f69aa66defafb10f0932dc5c649debab82e6c816e164c7b7ad8abbe974d15a94cd1c2937","0xd0639e479fa1ca8ee13fd966c216e662408ff00349068bdc9c6966c4ea10fe3e5f4d4ffc52db1898fe83742a8732e53322c178acb7113072c8dc6f82bbc00b99","0x73ee5cd601a19cd9bb95fe7be8b1566b73c51d3e7e375359c129b1d77bb4b3e6f06766bde6ff723360cee7f89abab428717f811f460ebf67f5186f75a9f4288d"]
export MPC_GROUP_ID="0x3726383e52fd4cb603498459e8a4a15d148566a51b3f5bfbbf3cac7b61647d04"
export MPC_PLAYER_1="0x3051bA2d313840932B7091D2e8684672496E9A4B"
export MPC_PLAYER_1_PK="59d1c6956f08477262c9e827239457584299cf583027a27c1d472087e8c35f21"
export MPC_PLAYER_2="0x7Ac8e2083E3503bE631a0557b3f2A8543EaAdd90"
export MPC_PLAYER_2_PK="6c326909bee727d5fc434e2c75a3e0126df2ec4f49ad02cdd6209cf19f91da33"
export MPC_PLAYER_3="0x3600323b486F115CE127758ed84F26977628EeaA"
export MPC_PLAYER_3_PK="5431ed99fbcc291f2ed8906d7d46fdf45afbb1b95da65fecd4707d16a6b3301b"
export MPC_GEN_PUBKEY="190712e558ac1ed8ee23774397d2b6e02239ff5e98acd0aa7faa893243b119031e3f9b1ea5ab1eda03dca6abfa89c50fab286141f9c419269651dfed2771c470"

# Create Group
cast send --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" --from $ROLE_DEFAULT_ADMIN --private-key $ROLE_DEFAULT_ADMIN_PK $MPC_MANAGER_ADDRESS "createGroup(bytes[],uint256)" $MPC_PLAYER_PUBKEY 1

# Key Gen
cast send --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" --from $ROLE_DEFAULT_ADMIN --private-key $ROLE_DEFAULT_ADMIN_PK $MPC_MANAGER_ADDRESS "requestKeygen(bytes32)" $MPC_GROUP_ID

# Report Key - Player 1
cast send --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" --from $MPC_PLAYER_1 --private-key $MPC_PLAYER_1_PK $MPC_MANAGER_ADDRESS "reportGeneratedKey(bytes32,uint256,bytes)" $MPC_GROUP_ID 1 $MPC_GEN_PUBKEY

# Report Key - Player 2
cast send --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" --from $MPC_PLAYER_2 --private-key $MPC_PLAYER_2_PK $MPC_MANAGER_ADDRESS "reportGeneratedKey(bytes32,uint256,bytes)" $MPC_GROUP_ID 2 $MPC_GEN_PUBKEY

# Report Key - Player 3
cast send --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" --from $MPC_PLAYER_3 --private-key $MPC_PLAYER_3_PK $MPC_MANAGER_ADDRESS "reportGeneratedKey(bytes32,uint256,bytes)" $MPC_GROUP_ID 3 $MPC_GEN_PUBKEY

pk=$(cast call --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" $MPC_MANAGER_ADDRESS "lastGenPubKey()" | sed 's/0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000040//g' )

addr=$(cast call --rpc-url "http://127.0.0.1:9650/ext/bc/C/rpc" $MPC_MANAGER_ADDRESS "lastGenAddress()" | sed 's/0x000000000000000000000000/0x/g')

echo "Mpc Wallet PubKey : $pk"
echo "Mpc Wallet Address: $addr"
