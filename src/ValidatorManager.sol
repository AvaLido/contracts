// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/utils/math/Math.sol";

import "./interfaces/IValidatorOracle.sol";
import "./Types.sol";

/**
 * @title Lido on Avalanche Validator Manager
 * @dev This contract is used to encapsulate logic for reading Validator state and computing
 * staking allocations. It contains a ValidatorOracle contract that is used to query the state
 * of validators on the network.
 */
contract ValidatorManager {
    IValidatorOracle vOracle;

    uint256 smallStakeThreshold = 100 ether;

    constructor(address oracleAddress) {
        vOracle = IValidatorOracle(oracleAddress);
    }

    /**
     * @notice Select valdators to dsitribute stake to. You should not need to call this function.
     * @dev This selects the validators to distribute stake to. It is called by the Lido contract
     * when we want to allocate a stake to validators.
     * In general, our aim is to maintain decentralisation of stake across many validator nodes.
     * Assuming that we end up handling a significant proportion of total stake in the network,
     * we want to a pseudo-even distribution of stake across all validators.
     * To be pragmatic, we use a greatly simplified option for small stakes where we just allocate
     * everything to a single pseudo-random validator.
     * For larger stakes, we use a packing-esque algorithm to allocate each validator a portion
     * of the total stake. This is clearly more expensive in gas, but only applies to people with more
     * capital anyway. They are free to use many transactions under the threshold which will have the same
     * distribution effect (assuming they are in different blocks).
     * @param amount The amount of stake to distribute.
     * @return validators The validator node ids to distribute the stake to.
     * @return allocations The amount of AVAX to allocate to each validator
     * @return remainder The remaining stake which could not be allocated.
     */
    function selectValidatorsForStake(uint256 amount)
        public
        view
        returns (
            string[] memory,
            uint256[] memory,
            uint256
        )
    {
        if (amount == 0) return (new string[](0), new uint256[](0), 0);

        Validator[] memory validators = vOracle.getAvailableValidatorsWithCapacity(smallStakeThreshold);

        // We have no nodes with capacity, don't do anything.
        if (validators.length == 0) {
            // TODO: Emit an event because this is not a great state to be in.
            return (new string[](0), new uint256[](0), amount);
        }

        // For cases where we're staking < 100, we just shove everything on one pseudo-random node.
        // This is significantly simpler and cheaper than spreading it out, and 100 will not be enough
        // to skew the distribution across the network.
        if (amount <= smallStakeThreshold) {
            uint256 i = uint256(keccak256(abi.encodePacked(block.timestamp))) % validators.length;
            string[] memory vals = new string[](1);
            vals[0] = validators[i].nodeId;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = amount;
            return (vals, amounts, 0);
        }

        // Compute the total free space so that we can tell if we're not going to be able to stake everything
        // right now.
        uint256 totalFreeSpace = 0;
        uint256[] memory freeSpaces = new uint256[](validators.length);
        for (uint256 index = 0; index < validators.length; index++) {
            uint256 free = vOracle.calculateFreeSpace(validators[index]);
            totalFreeSpace += free;
            freeSpaces[index] = free;
        }

        // If we have too much to stake, recompute the amount that we _can_ stake.
        // Keep track of the remaining value to return back to the caller.
        uint256 remainingUnstaked = 0;
        if (totalFreeSpace < amount) {
            uint256 newAmount = Math.min(amount, totalFreeSpace);
            remainingUnstaked = amount - newAmount;
            amount = newAmount;
        }

        // For larger amounts, we chunk it into N pieces.
        // We then continue to pack validators with each of those chunks in a round-robin
        // fashion, until we have nothing left to stake.
        uint256 chunkSize = amount / validators.length;

        // Because we need to create a fixed size array, we use every validator, and we set the amount to 0
        // if we can't stake anything on it. Callers must check this when using the result.
        uint256[] memory resultAmounts = new uint256[](validators.length);

        // Keep track of the amount we've staked
        uint256 n = 0;
        uint256 amountStaked = 0;
        while (amountStaked < amount) {
            uint256 remaining = amount - amountStaked;

            // Our actual fillable space is the initial free space, minus anything already allocated.
            uint256 freeSpace = freeSpaces[n] - resultAmounts[n];

            // Stake the smallest of (total remaining, space for this node, or 1 chunk).
            uint256 amountToStake = Math.min(remaining, Math.min(freeSpace, chunkSize));

            resultAmounts[n] += amountToStake;
            amountStaked += amountToStake;

            // Move on, and loop back to the start.
            n++;
            if (n > validators.length - 1) {
                n = 0;
            }
        }

        // Build a list of IDs in line with the amounts (as the order is not guaranteed to be stable
        // across transactions)
        string[] memory validatorIds = new string[](validators.length);
        for (uint256 i = 0; i < validators.length; i++) {
            validatorIds[i] = validators[i].nodeId;
        }

        return (validatorIds, resultAmounts, remainingUnstaked);
    }
}
