const { ethers } = require("ethers");
const fs = require("fs");
const assert = require("assert");
const utils = ethers.utils;

// RPC
const provider = new ethers.providers.JsonRpcProvider("http://127.0.0.1:9650/ext/bc/C/rpc");
const signer = provider.getSigner();

// Wallets
const deployer = new ethers.Wallet("56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027", provider);
const wendy = new ethers.Wallet("a7f3a9981d794d4849f296b0406bd4ee9aa5bfa03208954d93e5d61f965bb201", provider);
const sammy = new ethers.Wallet("0d4c5da04cb1a1292ac933f49722a49f20e4284ab268d4cd31119ac90e91117e", provider);

// Deployed contract address
const address = process.env.AVALIDO;
if (address == null) {
  throw new Error("Missing AVALIDO contract address env variable");
}

// Contract setup
const avalido = JSON.parse(fs.readFileSync("out/AvaLido.sol/AvaLido.json"));
const validator_manager = JSON.parse(fs.readFileSync("out/ValidatorManager.sol/ValidatorManager.json"));
const contract = new ethers.Contract(address, avalido["abi"], deployer);

// Validator Manager
async function setUpValidator() {
  const manager_address = await contract.validatorManager();
  const validator_contract = new ethers.Contract(manager_address, validator_manager["abi"], deployer);
  let result = await validator_contract.selectValidatorsForStake(utils.parseEther("10").toString());
}

beforeAll(() => {
  return setUpValidator();
});

test("Make a deposit", async () => {
  const start_balance = await contract.balanceOf(deployer.address);
  const deposit_amount = utils.parseEther("10");

  const options = { value: deposit_amount };
  const deposit = await contract.deposit(options);
  await deposit.wait();

  const end_balance = await contract.balanceOf(deployer.address);
  expect(end_balance.toString()).toBe(start_balance.add(deposit_amount).toString());
});

test("Request a withdrawal", async () => {
  const start_balance = await contract.balanceOf(deployer.address);
  const withdrawal_amount = utils.parseEther("10");

  const withdrawal = await contract.requestWithdrawal(withdrawal_amount);
  await withdrawal.wait();

  const end_balance = await contract.balanceOf(deployer.address);
  expect(end_balance.toString()).toBe(start_balance.sub(withdrawal_amount).toString());
});
