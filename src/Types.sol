// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

struct UnstakeRequest {
    address requester; // The user who requested the unstake.
    uint64 requestedAt; // The block.timestamp when the unstake request was made.
    uint256 amountRequested; // The amount of stAVAX requested to be unstaked.
    uint256 amountFilled; // The amount of free'd AVAX that has been allocated to this request.
    uint256 amountClaimed; // The amount of AVAX that has been claimed by the requester.
}

struct Validator {
    uint64 stakeEndTime;
    uint256 primaryStakeAmount;
    uint256 delegatedAmount;
    string id;
}
