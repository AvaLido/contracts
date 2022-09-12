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
      //   console.log(defaultAbiCoder.encode(["string[]"], [nodes]));

      console.log(
        defaultAbiCoder.encode(
          ["string[]"],
          [
            [
              "NodeID-4CWTbdvgXHY1CLXqQNAp22nJDo5nAmts6",
              "NodeID-3VWnZNViBP2b56QBY7pNJSLzN2rkTyqnK",
              "NodeID-LQwRLm4cbJ7T2kxcxp4uXCU5XD8DFrE1C",
              "NodeID-84KbQHSDnojroCVY7vQ7u9Tx7pUonPaS",
              "NodeID-4FD94p7B8o4MzFHpazLN6jbTgXPpf8mHP",
            ],
          ]
        )
      );
    });
  });

  req.write(JSON.stringify(requestData));
  req.end();
}

main();
