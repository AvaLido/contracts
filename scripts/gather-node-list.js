const { defaultAbiCoder } = require("ethers/lib/utils");
const https = require("https");
const fs = require("fs");

function main() {
  const requestData = {
    jsonrpc: "2.0",
    method: "platform.getCurrentValidators",
    params: {},
    id: 1,
  };

  const options = {
    hostname: "api.avax-test.network",
    path: "/ext/bc/P",
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
  };

  const req = https.request(options, (res) => {
    let returnData = "";
    res.on("data", (chunk) => {
      if (chunk) {
        returnData += chunk;
      }
    });

    res.on("end", () => {
      const data = JSON.parse(returnData);
      const nodes = data.result.validators.map((v) => {
        return v.nodeID;
      });

      fs.writeFileSync("./out/node-output.json", JSON.stringify(nodes));
      console.log(defaultAbiCoder.encode(["bool", "uint256"], [true, nodes.length]));
    });

    res.on("error", () => {
      console.log(defaultAbiCoder.encode(["bool", "uint256"], [false, 0]));
    });
  });

  req.write(JSON.stringify(requestData));
  req.end();
}

main();
