// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";

import "./interfaces/IValidatorOracle.sol";
import "./Types.sol";

contract ValidatorOracle is BaseValidatorOracle, AccessControlEnumerable {
    Validator[] validators;
    mapping(string => bool) validatorAllowlist;

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier onlyAdmin() {
        hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _;
    }

    function addValidatorToAllowlist(string memory validatorId) public onlyAdmin {
        validatorAllowlist[validatorId] = true;
    }

    function removeValidatorFromAllowlist(string memory validatorId) public onlyAdmin {
        delete validatorAllowlist[validatorId];
    }

    function getAvailableValidators() public view override returns (Validator[] memory) {
        return validators;
    }

    function getAvailableValidatorsWithCapacity(uint256 amount) public view override returns (Validator[] memory) {
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

    function isInAllowlist(string memory validatorId) public view returns (bool) {
        return validatorAllowlist[validatorId];
    }

    // TODO: functions which set the validator data.
    // NOTE: We should take the allowlist into account when deciding which validators to write data for,
    // this will be much simpler (and more efficient) than taking all data and filtering afterwards.
}
