// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

// Test support
import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

import "../test/helpers.sol";

import "../AvaLido.sol";
import "../Oracle.sol";
import "../ValidatorSelector.sol";

// Set nodes for the oracle
// WARNING: It is important to note that the `gather-node-list` script does some
// *important filtering*. In order to cut down on the number of validators which we
// need to upload to the chain (which is slow and expensive), we filter out ones which
// will never match our staking criteria here.
// The parameters which are used in the script are derived from the contracts, so that
// they do not become out of sync, even if changed.
contract SetNodes is Script {
    // forge script src/deploy/OracleAddNodes.t.sol --sig "startUpdate(address, address)" --ffi --rpc-url $RPC_URL --private-key $FORGE_PK [oracle] [avalido] --broadcast
    function startUpdate(address oracleAddress, address avaAddress) public {
        AvaLido avalido = AvaLido(avaAddress);
        Oracle oracle = Oracle(oracleAddress);
        ValidatorSelector selector = ValidatorSelector(address(avalido.validatorSelector()));

        string[] memory inputs = new string[](4);
        inputs[0] = "node";
        inputs[1] = "./scripts/gather-node-list.js";
        inputs[2] = vm.toString(avalido.stakePeriod());
        inputs[3] = vm.toString(selector.smallStakeThreshold());

        bytes memory res = vm.ffi(inputs);
        (bool success, uint256 amount) = abi.decode(res, (bool, uint256));
        require(success, "couldn't get node list");

        console.log("Got nodes:", amount);
        console.log("Start 'addNodes' with index 0");

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
