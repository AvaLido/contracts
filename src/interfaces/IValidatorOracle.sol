// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "../Types.sol";

interface IValidatorOracle {
    function getAvailableValidators() external view returns (Validator[] memory);

    function getAvailableValidatorsWithCapacity(uint256 amount) external view returns (Validator[] memory);

    function calculateFreeSpace(Validator memory val) external pure returns (uint256);
}

abstract contract BaseValidatorOracle is IValidatorOracle {
    function getAvailableValidators() external view virtual returns (Validator[] memory);

    function getAvailableValidatorsWithCapacity(uint256 amount) external view virtual returns (Validator[] memory);

    function calculateFreeSpace(Validator memory val) public pure returns (uint256) {
        return (val.primaryStakeAmount * 4) - val.delegatedAmount;
    }
}
