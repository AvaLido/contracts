# Lido on Avalanche Contracts

### Setup

One time:

1. Install [`forge`](https://github.com/gakonst/foundry#installation).
1. Run `foundryup`
1. Run `forge install` in this repo to install dependencies.
1. Run `forge test` to check everything is working.

To see any `forge` assertion failure details or console logs, run `forge test` with `-vv`

**Avalanche local network**

1. Make sure you have `go` installed (`brew install go`).
1. Install the `Taskfile` binary with `brew install go-task/tap/go-task` (or [see alternatives](https://taskfile.dev/#/installation))
1. Download an `avalanchego` binary (or build from source) https://github.com/ava-labs/avalanchego/releases.
1. Extract the binary, and place the `build` folder in the `network` directory.
1. `cd` into the `network` directory and run `go mod download`.
1. From within the `network` directory run `go run main.go` or from the `contracts` directory run `go run network/main.go` to run a local Avalanche network.

The local network has a few pre-funded accounts to make development easier:

- `Contract Deployer` - `0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC` PK `56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027`
- 🐳 `Wendy` - `0xf195179eEaE3c8CAB499b5181721e5C57e4769b2` PK `a7f3a9981d794d4849f296b0406bd4ee9aa5bfa03208954d93e5d61f965bb201`
- 🦐 `Sammy` - `0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2` PK `0d4c5da04cb1a1292ac933f49722a49f20e4284ab268d4cd31119ac90e91117e`
- 🔮 `Oracle 1` - `0x03C1196617387899390d3a98fdBdfD407121BB67` PK `a54a5d692d239287e8358f27caee92ab5756c0276a6db0a062709cd86451a855`
- 🔮 `Oracle 2` - `0x6C58f6E7DB68D9F75F2E417aCbB67e7Dd4e413bf` PK `86a5e025e16a96e2706d72fd6115f2ee9ae1c5dfc4c53894b70b19e6fc73b838`
- 🔮 `Oracle 3` - `0xa7bB9405eAF98f36e2683Ba7F36828e260BD0018` PK `d876abc4ef78972fc733651bfc79676d9a6722626f9980e2db249c22ed57dbb2`
- 🔮 `Oracle 4` - `0xE339767906891bEE026285803DA8d8F2f346842C` PK `6353637e9d5cdc0cbc921dadfcc8877d54c0a05b434a1d568423cb918d582eac`
- 🔮 `Oracle 5` - `0x0309a747a34befD1625b5dcae0B00625FAa30460` PK `c847f461acdd47f2f0bf08b7480d68f940c97bbc6c0a5a03e0cbefae4d9a7592`
- 🐪 `Mpc Player 1` - `0x3051bA2d313840932B7091D2e8684672496E9A4B` PK `59d1c6956f08477262c9e827239457584299cf583027a27c1d472087e8c35f21`
- 🐪 `Mpc Player 2` - `0x7Ac8e2083E3503bE631a0557b3f2A8543EaAdd90` PK `6c326909bee727d5fc434e2c75a3e0126df2ec4f49ad02cdd6209cf19f91da33`
- 🐪 `Mpc Player 3` - `0x3600323b486F115CE127758ed84F26977628EeaA` PK `5431ed99fbcc291f2ed8906d7d46fdf45afbb1b95da65fecd4707d16a6b3301b`

The network stores state in the `node-N` directories in the `network` folder. This means you can kill and restart the network without losing state. You should be able to use Metamask like normal to test out the network.

To setup Metamask, add:

RPC URL: `http://127.0.0.1:9650/ext/bc/C/rpc`
Chain ID: `43112`

### Deployment

You can deploy to the local network with `task deploy` like so:

```
task deploy -- AvaLido [ARGS]
```

This uses the pre-funded AVAX account label "Contract deployer" above. The contract requires these arguments to deploy:

1. lidoFeeAddress - The address of the lido controlled wallet which collects revenue
1. authorFeeAddress - The address of the hyperelliptic/rockx wallet which collects revenue
1. validatorManagerAddress - The address of the validator manager contract to use
1. \_mpcManagerAddress - The address of the MPC manager contract which manages MPC operations.

The validatorManagerAddress requires deploying the `ValidatorManager` contract, which in turn requires the `ValidatorOracle` contract address.

If you don't care about these args and just want some defaults for development, you can use:

```
task deploy-default
```

If you don't care about the actual cross-chain MPC operations and just want a smart contract development environment, you can use the following task to initialize the contract with a placeholder key:

```
task init-mpc-fake -- <Deployed MpcManager Contract Address>
```
