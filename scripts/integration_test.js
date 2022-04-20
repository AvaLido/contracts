const { ethers } = require("ethers");
const fs = require("fs");

// RPC
const provider = new ethers.providers.JsonRpcProvider("http://127.0.0.1:9650/ext/bc/C/rpc");
const signer = provider.getSigner();

// Wallets
const deployer = new ethers.Wallet("56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027", provider);
const wendy = new ethers.Wallet("a7f3a9981d794d4849f296b0406bd4ee9aa5bfa03208954d93e5d61f965bb201", provider);
const sammy = new ethers.Wallet("0d4c5da04cb1a1292ac933f49722a49f20e4284ab268d4cd31119ac90e91117e", provider);

// Contract
const address = "0x52c84043cd9c865236f11d9fc9f56aa003c1f922";
const avalido = JSON.parse(fs.readFileSync("out/AvaLido.sol/AvaLido.json"));
const abi = avalido["abi"];
const contract = new ethers.Contract(address, abi, deployer);

// Read contract
contract.name().then((data) => console.log(data));
contract.symbol().then((data) => console.log(data));
