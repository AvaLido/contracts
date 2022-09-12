// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

// Test support
import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../test/helpers.sol";

// Contracts for deploy
import "../OracleManager.sol";
import "../Oracle.sol";
import "../AvaLido.sol";

contract Deploy is DSTest, Helpers {
    // Set nodes for the Fuji network
    // Usage: forge script src/deploy/OracleFujiNodes.t.sol --sig "setNodes(address)" --broadcast --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> [address]
    // Syntax is identical to `cast`
    function setNodes(address oracleAddress) public {
        // cheats.startBroadcast();

        string[] memory inputs = new string[](2);
        inputs[0] = "node";
        inputs[1] = "./scripts/fuji-get-nodes.js";

        bytes memory res = cheats.ffi(inputs);
        string[] memory nodes = abi.decode(res, (string[]));

        // Oracle
        Oracle oracle = Oracle(address(oracleAddress));
        oracle.setNodeIDList(nodes);

        // cheats.stopBroadcast();
    }
}
