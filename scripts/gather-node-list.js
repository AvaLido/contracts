const { defaultAbiCoder } = require("ethers/lib/utils");
const https = require("https");
const fs = require("fs");

// This is also used in the Oracle. Technically if we filter everything
// here then there's nothing for the oracle to filter, but I'm going to leave it in both
// because this allows us to be a little smarter if needed. For example, we could set a
// loose limit here, like 4%, and in the oracle choose 2%, but allow up to 4 if we're
// running out of stake room.
const MAX_DELEGATION_FEE = 200;

function main() {
  const stakePeriodSeconds = Number(process.argv[2]);
  if (isNaN(stakePeriodSeconds) || stakePeriodSeconds <= 0) {
    throw new Error("Invalid stake period");
  }

  const smallStakeThresholdWei = BigInt(process.argv[3]);
  if (smallStakeThresholdWei <= 0) {
    throw new Error("Invalid stake threshold");
  }

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

      // Filter out some nodes based on the params passed to the script. This avoids
      // needing to upload validators to the oracle which can never be valid based on
      // those params. Note that we're only filtering static parameters which would guarantee
      // exclusion from receiving stake. Things which can fluctuate between the node upload
      // (e.g. uptime and space) must also be filtered in each oracle report.
      const filtered = data.result.validators.filter((validator) => {
        // If the fee is too high, remove it.
        const fee = Number(validator.delegationFee) * 100;
        if (fee > MAX_DELEGATION_FEE) {
          return false;
        }

        // If there's less than 1 of our stake periods left, remove it.
        const remaining = validator.endTime - Date.now() / 1000;
        if (remaining < stakePeriodSeconds) {
          return false;
        }

        // If there's less than our minimum free space, removeit.
        const stakeAmountNavax = BigInt(validator.stakeAmount);
        const maxAmountNavax = stakeAmountNavax * BigInt(4);
        const usedAmountNavax = (validator.delegators || []).reduce((memo, del) => {
          return memo + BigInt(del.stakeAmount);
        }, BigInt(0));
        const remainingSpaceNavax = maxAmountNavax - usedAmountNavax;
        const remainingSpaceWei = remainingSpaceNavax * BigInt(1000000000);
        if (remainingSpaceWei < smallStakeThresholdWei) {
          return false;
        }

        // Otherwise, you're in.
        return true;
      });

      const nodes = filtered.map((v) => {
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
