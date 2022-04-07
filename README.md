# Lido on Avalanche Contracts

### Setup

One time:

1. Install [`forge`](https://github.com/gakonst/foundry#installation).
1. Run `foundryup`
1. Run `forge install` in this repo to install dependencies.
1. Run `forge test` to check everything is working.

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
task deploy -- AvaLido
```

This uses the pre-funded AVAX account label "Contract deployer" above.

### Interaction

Use `cast` to call contract functions directly, like: `cast call <address> "deposit()" --rpc-url http://127.0.0.1:9650/ext/bc/C/rpc`.

Or, you can use the `task` which has the RPC URL pre-set: `cast call -- <address> "deposit()"`