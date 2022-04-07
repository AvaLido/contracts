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

The local network has a few pre-funded accounts to make development easiser.

TODO

- `Contract Deployer` - `0x...`
- 🐳 `Wendy` - `0x...`
- 🦐 `Simon` - `0x...`

### Deployment

You can deploy with `forge create`. To
