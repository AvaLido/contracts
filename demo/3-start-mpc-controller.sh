#!/usr/bin/env bash

sks=("59d1c6956f08477262c9e827239457584299cf583027a27c1d472087e8c35f21" "6c326909bee727d5fc434e2c75a3e0126df2ec4f49ad02cdd6209cf19f91da33" "5431ed99fbcc291f2ed8906d7d46fdf45afbb1b95da65fecd4707d16a6b3301b")
MPC_MANAGER_ADDRESS=$(cat MPC_MANAGER_ADDRESS)
function create_config(){
    id=$1
    sk=${sks[$(expr ${id} - 1)]}
    read -r -d '' CFG <<- EOM
enableDevMode: true
controllerId: "mpc-controller-0${id}"
controllerKey: "${sk}"
coordinatorAddress: "${MPC_MANAGER_ADDRESS}"
mpcServerUrl: "http://localhost:9000"
ethRpcUrl: "http://localhost:9650/ext/bc/C/rpc"
ethWsUrl: "ws://127.0.0.1:9650/ext/bc/C/ws"
cChainIssueUrl: "http://localhost:9650"
pChainIssueUrl: "http://localhost:9650"
confignetwork:
  networkId: 1337
  chainId: 43112
  cChainId: "2cRHidGTGMgWSMQXVuyqB86onp69HTtw6qHsoHvMjk9QbvnijH"
  avaxId: "BUuypiq2wyuLMvyhzFXcPyxPMCgSp7eeDohhQRqTChoBjKziC"
  importFee: 1000000
  gasPerByte: 1
  gasPerSig: 1000
  gasFixed: 10000
configdbbadger:
  badgerDbPath: "./mpc_controller_db${id}"
EOM

# echo $config
echo -e "$CFG" > config${id}.yaml
}

create_config 1
create_config 2
create_config 3



pkill -f mpc-controller

sleep 5

mpc-controller --configFile ./config1.yaml > logs/mpc-controller1.log 2>&1 &
mpc-controller --configFile ./config2.yaml > logs/mpc-controller2.log 2>&1 &
mpc-controller --configFile ./config3.yaml > logs/mpc-controller3.log 2>&1 &
