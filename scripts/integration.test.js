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
const avalido_address = process.env.AVALIDO;
const oracle_address = process.env.VALIDATOR_ORACLE;
if (avalido_address == null || oracle_address == null) {
  throw new Error("Missing AVALIDO or VALIDATOR_ORACLE contract address env variables");
}

// Contract setup
const avalido = JSON.parse(fs.readFileSync("out/AvaLido.sol/AvaLido.json"));
const contract = new ethers.Contract(avalido_address, avalido["abi"], deployer);

// Oracle contract setup
const oracle = JSON.parse(fs.readFileSync("out/ValidatorOracle.sol/ValidatorOracle.json"));
const oracle_contract = new ethers.Contract(oracle_address, oracle["abi"], deployer);

// Validator Manager
async function setUpValidator() {
  const manager_address = await contract.validatorManager();
  const validator_manager = JSON.parse(fs.readFileSync("out/ValidatorManager.sol/ValidatorManager.json"));
  const validator_contract = new ethers.Contract(manager_address, validator_manager["abi"], deployer);
  await validator_contract.selectValidatorsForStake(utils.parseEther("1000").toString());
}

function decodeAndRethrowError(error) {
  const codes = [
    "InvalidStakeAmount()",
    "TooManyConcurrentUnstakeRequests()",
    "NotAuthorized()",
    "ClaimTooLarge()",
    "InsufficientBalance()",
    "NoAvailableValidators()",
  ];

  // TODO: This is bad and you should feel bad
  // Attempt to parse. If we can't, this isn't one of ours, just rethrow
  const split = error.message.split('"data":"');
  if (split.length < 2) {
    throw error;
  }

  const error_code = split[1].slice(0, 10);
  for (const code of codes) {
    const hash = utils.keccak256(utils.toUtf8Bytes(code));
    if (hash.startsWith(error_code)) {
      throw "Error from contract: " + code;
    }
  }
  throw "Unrecognized error from contract. Check that all errors have been imported.";
}

async function makeDeposit(amount) {
  const deposit = await contract.deposit({ value: amount });
  await deposit.wait();
}

beforeAll(() => {
  return setUpValidator();
});

test("Make a deposit", async () => {
  const start_balance = await contract.balanceOf(deployer.address);
  const deposit_amount = utils.parseEther("10");
  await makeDeposit(deposit_amount);
  const end_balance = await contract.balanceOf(deployer.address);
  expect(end_balance.toString()).toBe(start_balance.add(deposit_amount).toString());
});

test("Request a withdrawal", async () => {
  try {
    const start_balance = await contract.balanceOf(deployer.address);
    const withdrawal_amount = utils.parseEther("10");

    const withdrawal = await contract.requestWithdrawal(withdrawal_amount);
    await withdrawal.wait();

    const end_balance = await contract.balanceOf(deployer.address);
    expect(end_balance.toString()).toBe(start_balance.sub(withdrawal_amount).toString());
  } catch (error) {
    decodeAndRethrowError(error);
  }
});

test("Claim a withdrawal request", async () => {
  try {
    const start_staked = await contract.amountStakedAVAX();

    // Add a fake validator to stake with
    // TODO: Test will fail when we start respecting stake end times. If you're reading this, add a test for it!
    const stake_amount = utils.parseEther("1000").toString();
    const validator = await oracle_contract._TEMP_addValidator(0, stake_amount, 0, "integration");
    await validator.wait();

    // Amount deposited from previous unit test
    // TODO: These should really be indepenedent tests
    const deposit_amount = utils.parseEther("10");

    // Initiate stake with outstanding AVAX
    const stake = await contract.initiateStake();
    await stake.wait();

    let staked = await contract.amountStakedAVAX();
    expect(staked.toString()).toBe(start_staked.add(deposit_amount).toString()); // Stake increased

    // Fake receiving AVAX back from MPC
    const receive = await contract.receivePrincipalFromMPC({ value: deposit_amount });
    await receive.wait();

    // Claim most recent withdrawal request
    const last_request = (await contract.unstakeRequestCount(deployer.address)) - 1;

    // TODO: Occasionally fails here on incorrect unstake request – might need more wait()
    const requester = (await contract.unstakeRequests(last_request))["requester"];
    expect(deployer.address).toBe(requester);

    const claim = await contract.claim(last_request, deposit_amount);
    await claim.wait();

    staked = await contract.amountStakedAVAX();
    expect(staked.toString()).toBe(start_staked.toString()); // Stake restored
  } catch (error) {
    decodeAndRethrowError(error);
  }
}, 600_000); // TODO: Should be a more thoughtful timeout

test("Randomly deposit or withdraw 100 times", async () => {
  // TODO: ⚠️ TEMPORARILY DISABLED UNTIL CLAIMING INTEGRATED
  return;

  try {
    const start_balance = await contract.balanceOf(deployer.address);

    let deposits_cumulative = utils.parseEther("0");
    let withdrawals_cumulative = utils.parseEther("0");

    for (i = 0; i < 100; i++) {
      const balance = await contract.balanceOf(deployer.address);

      let raw_amount = Math.pow(2 * Math.random() + 0.5, 10); // Roughly 0.001 to 10k eth
      raw_amount = Math.round(raw_amount * 1000) / 1000;
      const amount = utils.parseEther(raw_amount.toString());

      // Prevent attempting to withdraw more than is deposited
      const isWithdrawal = Math.random() < 0.5 && balance.gt(amount);

      if (isWithdrawal) {
        withdrawals_cumulative = withdrawals_cumulative.add(amount);
        console.log(
          "Withdrawal " + utils.formatEther(amount) + " (Cumulative " + utils.formatEther(withdrawals_cumulative) + ")"
        );
        const withdrawal = await contract.requestWithdrawal(amount);
        await withdrawal.wait(); // TODO: Should wait at end rather than every step
      } else {
        deposits_cumulative = deposits_cumulative.add(amount);
        console.log(
          "Deposit " + utils.formatEther(amount) + " (Cumulative " + utils.formatEther(withdrawals_cumulative) + ")"
        );
        const deposit = await contract.deposit({ value: amount });
        await deposit.wait();
      }
    }

    const end_balance = await contract.balanceOf(deployer.address);
    const expected_balance = start_balance.add(deposits_cumulative).sub(withdrawals_cumulative);
    expect(end_balance.toString()).toBe(total.toString());
  } catch (error) {
    decodeAndRethrowError(error);
  }
}, 600_000); // TODO: Should be a more thoughtful timeout
