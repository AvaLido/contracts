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
1. Extract the binary, and place the `build` folder it in the `network` directory.
1. Run `go run network/main.go` to run a local Avalanche network.

The local network has a few pre-funded accounts to make development easiser:

- `Contract Deployer` - `0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC` PK `56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027`
- 🐳 `Wendy` - `0xf195179eEaE3c8CAB499b5181721e5C57e4769b2` PK `a7f3a9981d794d4849f296b0406bd4ee9aa5bfa03208954d93e5d61f965bb201`
- 🦐 `Sammy` - `0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2` PK `0d4c5da04cb1a1292ac933f49722a49f20e4284ab268d4cd31119ac90e91117e`

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
1. \_mpcWalletAddress - The address of the MPC wallet to send stakes to.

The validatorManagerAddress requires deploying the `ValidatorManager` contract, which in turn requires the `ValidatorOracle` contract address.

If you don't care about these args and just want some defaults for development, you can use:

```
task deploy-default
```

### Interaction

Use `cast` to call contract functions directly. Examples:

- Calling a method: `cast call <address> "deposit()" --rpc-url http://127.0.0.1:9650/ext/bc/C/rpc`
- Sending AVAX to a `payable` method: `cast send --rpc-url http://127.0.0.1:9650/ext/bc/C/rpc --from <address> --private-key <key> --value 1 <address> "deposit()"`

You can also use the `task` command, which has the RPC URL pre-set: `task call -- <address> "deposit()"`

To pass arguments to a function, you'll need to split them out: `task call -- <address> "deposit(uint256)" 1`

### Testing

Unit tests are run with `forge test`. Integration tests are run using [Jest](https://jestjs.io/docs/getting-started_) with `jest integration`

Integration tests expect that the `$AVALIDO` environment variable has been set to the deployed contract address. Deploying via `. ./scripts/deploy-local.sh` will set this automagically.

To test for well-known vulnerabilities with the [Slither static analyzer](https://github.com/crytic/slither), run `slither .` in the main directory.