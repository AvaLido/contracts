// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

struct Validator {
    uint64 stakeEndTime;
    uint256 primaryStakeAmount;
    uint256 delegatedAmount;
    string id;
}
