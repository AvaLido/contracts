const { defaultAbiCoder } = require("ethers/lib/utils");
const { argv } = require("process");
const fs = require("fs");

function main() {
  const batchSize = argv[2];
  const start = argv[3];
  const nodes = JSON.parse(fs.readFileSync("./out/node-output.json"));

  if (start > nodes.length - 1) {
    console.error("Invalid start offset");
    process.exit(1);
  }

  const toReturn = nodes.slice(start, start + batchSize);
  console.log(defaultAbiCoder.encode(["string[]"], [toReturn]));
}

main();
