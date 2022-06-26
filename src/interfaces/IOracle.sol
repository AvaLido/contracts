// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "../Types.sol";

interface IOracle {
    function receiveFinalizedReport(uint256 _epochId, Validator[] calldata _reportData) external;

    function getLatestValidators() external view returns (Validator[] memory);

    function nodeIdByValidatorIndex(uint256 index) external view returns (string memory);

    function validatorCount() external view returns (uint256);
}
