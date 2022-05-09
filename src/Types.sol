// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

interface Empty {}

struct UnstakeRequest {
    address requester; // The user who requested the unstake.
    uint64 requestedAt; // The block.timestamp when the unstake request was made.
    uint256 amountRequested; // The amount of stAVAX requested to be unstaked.
    uint256 amountFilled; // The amount of free'd AVAX that has been allocated to this request.
    uint256 amountClaimed; // The amount of AVAX that has been claimed by the requester.
}

struct Validator {
    uint64 stakeEndTime; // The Unix timestamp in seconds when the validator expires.
    uint256 primaryStakeAmount; // The intial stake amount the validator was instantiated with.
    uint256 delegatedAmount; // The amount of AVAX delegated to the validator.
    string nodeId; // The id of the validator node.
}

struct ValidatorData {
    string nodeId; // The id of the validator node.
    uint64 stakeEndTime; // The Unix timestamp in seconds when the validator expires.
    uint256 freeSpace; // The amount of AVAX free on the given node.
}
