// #!/bin/sh
// VALIDATORS=$(curl -X POST -d '{
//     "jsonrpc": "2.0",
//     "method": "platform.getCurrentValidators",
//     "params": {},
//     "id": 1
// }' -H 'content-type:application/json;' https://api.avax-test.network/ext/bc/P)

const { defaultAbiCoder } = require("ethers/lib/utils");

// NODEIDS=$(echo $VALIDATORS | jq ".result.validators[] | .nodeID")

// echo $NODEIDS

function main() {
  //   const abi = ethers.utils.defaultAbiCoder;
  console.log(defaultAbiCoder.encode(["string[]"], [["test", "test"]]));
}

main();
