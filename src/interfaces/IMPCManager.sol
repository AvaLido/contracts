// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

interface IMPCManager {
    function serveStake(string calldata nodeID, uint256 amount, uint256 startTime, uint256 endTime) external;
}