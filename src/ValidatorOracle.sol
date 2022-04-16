// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

contract ValidatorOracle {
    struct Validator {
        uint64 stakeEndTime;
        uint256 primaryStakeAmount;
        uint256 delegatedAmount;
        string id;
    }

    Validator[] validators;

    function __debug_setValidators(Validator[] memory vals) public {
        validators = vals;
    }

    function getAvailableValidators() public view returns (Validator[] memory) {
        return validators;
    }

    function getAvailableValidatorsWithCapacity(uint256 amount) public view returns (Validator[] memory) {
        // TODO: Can we re-think a way to filter this without needing to iterate twice?
        // We can't do it client-side because it happens at stake-time, and we do not want
        // clients to control where the stake goes.
        uint256 count = 0;
        for (uint256 index = 0; index < validators.length; index++) {
            if (calculateFreeSpace(validators[index]) < amount) {
                count++;
            }
        }

        Validator[] memory result = new Validator[](count);
        for (uint256 index = 0; index < validators.length; index++) {
            if (calculateFreeSpace(validators[index]) < amount) {
                result[index] = validators[index];
            }
        }
        return result;
    }

    function calculateFreeSpace(Validator memory val) internal pure returns (uint256) {
        return (val.primaryStakeAmount * 4) - val.delegatedAmount;
    }
}
