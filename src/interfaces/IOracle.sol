// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "../Types.sol";

interface IOracle {
    function receiveFinalizedReport(uint256 _epochId, ValidatorData[] calldata _reportData) external;

    function getAllValidatorDataByEpochId(uint256 _epochId) external view returns (ValidatorData[] memory);

    function selectValidatorsForStake(uint256 amount, uint256 epochId)
        external
        view
        returns (
            string[] memory,
            uint256[] memory,
            uint256
        );
}
