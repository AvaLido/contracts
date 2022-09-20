// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

// Test support
import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

import "../test/helpers.sol";

import "../Oracle.sol";

// Set nodes for the oracle
contract SetNodes is Script {
    // forge script src/deploy/OracleAddNodes.t.sol --sig "startUpdate(address)" --ffi --rpc-url $RPC_URL --private-key $FORGE_PK [address] --broadcast
    function startUpdate(address oracleAddress) public {
        string[] memory inputs = new string[](2);
        inputs[0] = "node";
        inputs[1] = "./scripts/gather-node-list.js";

        bytes memory res = vm.ffi(inputs);
        (bool success, uint256 amount) = abi.decode(res, (bool, uint256));
        require(success, "couldn't get node list");

        console.log("Got nodes:", amount);
        console.log("Start 'addNodes' with index 0");

        Oracle oracle = Oracle(address(oracleAddress));
        vm.broadcast();
        oracle.startNodeIDUpdate();
    }

    // forge script src/deploy/OracleAddNodes.t.sol --sig "addNodes(address,uint256)" --ffi  --rpc-url $RPC_URL --private-key $FORGE_PK [address] [startIndex] --broadcast
    function addNodes(address oracleAddress, uint256 startIndex) public {
        uint256 batchSize = 50;
        string[] memory inputs = new string[](4);
        inputs[0] = "node";
        inputs[1] = "./scripts/read-node-list.js";
        inputs[2] = Strings.toString(batchSize);
        inputs[3] = Strings.toString(startIndex);

        bytes memory res = vm.ffi(inputs);
        string[] memory nodes = abi.decode(res, (string[]));

        // We're on the last batch if we don't get a full one, or we get 0
        if (nodes.length < batchSize || nodes.length == 0) {
            console.log("Completed all nodes");
        } else {
            console.log("Next index to use: ", startIndex + batchSize);
        }

        Oracle oracle = Oracle(address(oracleAddress));
        vm.broadcast();
        oracle.appendNodeIDs(nodes);
    }

    // forge script src/deploy/OracleAddNodes.t.sol --sig "endUpdate(address)" --rpc-url $RPC_URL --private-key $FORGE_PK [address] [startIndex]
    function endUpdate(address oracleAddress) public {
        Oracle oracle = Oracle(address(oracleAddress));
        vm.broadcast();
        oracle.endNodeIDUpdate();
    }
}
