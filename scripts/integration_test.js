const { ethers } = require("ethers");
const fs = require("fs");
const utils = ethers.utils;

// Command line args
const args = process.argv;
if (args.length < 3) {
  const filename = require("path").basename(__filename);
  console.log("Usage: node " + filename + " [contract address]");
  process.exit();
}
const address = args[2];

// RPC
const provider = new ethers.providers.JsonRpcProvider("http://127.0.0.1:9650/ext/bc/C/rpc");
const signer = provider.getSigner();

// Wallets
const deployer = new ethers.Wallet("56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027", provider);
const wendy = new ethers.Wallet("a7f3a9981d794d4849f296b0406bd4ee9aa5bfa03208954d93e5d61f965bb201", provider);
const sammy = new ethers.Wallet("0d4c5da04cb1a1292ac933f49722a49f20e4284ab268d4cd31119ac90e91117e", provider);

// Contract
const avalido = JSON.parse(fs.readFileSync("out/AvaLido.sol/AvaLido.json"));
const abi = avalido["abi"];
const contract = new ethers.Contract(address, abi, deployer);

// Read
// contract.name().then((data) => console.log(data));
// contract.symbol().then((data) => console.log(data));

// Deposit
async function deposit() {
  // Read balance
  let balance = await contract.balanceOf(deployer.address);
  console.log(utils.formatEther(balance));

  // Make new deposit
  const options = { value: utils.parseEther("10") };
  let deposit = await contract.deposit(options);
  console.log(deposit);

  // Read back balance again
  balance = await contract.balanceOf(deployer.address);
  console.log(utils.formatEther(balance));

  // Withdraw
  try {
    let withdrawal = await contract.requestWithdrawal(balance);
    console.log(withdrawal);
  } catch (e) {
    console.log(e);
  }

  // Read back balance again
  balance = await contract.balanceOf(deployer.address);
  console.log(utils.formatEther(balance));
}
deposit();
