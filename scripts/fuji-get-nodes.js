const { defaultAbiCoder } = require("ethers/lib/utils");
const https = require("https");

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
      console.log(defaultAbiCoder.encode(["string[]"], [nodes]));
    });
  });

  req.write(JSON.stringify(requestData));
  req.end();
}

main();
