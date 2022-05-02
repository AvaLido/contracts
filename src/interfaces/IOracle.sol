// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "../Types.sol";

interface IOracle {
    function receiveFinalizedReport(uint256 _epochId, bytes32 _hashedReportData) external;
}
