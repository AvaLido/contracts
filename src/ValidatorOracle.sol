// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";

import "./interfaces/IValidatorOracle.sol";
import "./Types.sol";

/**
 * @title Lido on Avalanche Validator Oracle
 * @dev This contract is used to provide data on the Avalanche validators.
 * For efficiency, we only expect data for the validators which we wish to use.
 * If other validator data is posted to the contract, it will be ignored based
 * on the contents of the allowlist.
 */
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

    // Temporary function to force setting validators whilst the oracle is not built.
    function _TEMP_setValidators(Validator[] memory vals) public {
        delete validators;
        for (uint256 i = 0; i < vals.length; i++) {
            validators.push(vals[i]);
        }
    }

    function _TEMP_addValidator(
        uint64 stakeEndTime,
        uint256 primaryStakeAmount,
        uint256 delegatedAmount,
        string memory id
    ) public {
        validators.push(Validator(stakeEndTime, primaryStakeAmount, delegatedAmount, id));
    }

    /**
     * @notice Gets the validators which have capacity to handle the given amount of AVAX.
     * @dev Returns an dynamic array of validators.
     * @param amount The amount of AVAX to allocate in total.
     * @return validators The validators which have capacity to handle the given amount of AVAX.
     */
    function getAvailableValidatorsWithCapacity(uint256 amount) public view override returns (Validator[] memory) {
        // TODO: Can we re-think a way to filter this without needing to iterate twice?
        // We can't do it client-side because it happens at stake-time, and we do not want
        // clients to control where the stake goes.
        uint256 count = 0;
        for (uint256 index = 0; index < validators.length; index++) {
            if (calculateFreeSpace(validators[index]) >= amount) {
                count++;
            }
        }

        Validator[] memory result = new Validator[](count);
        for (uint256 index = 0; index < validators.length; index++) {
            if (calculateFreeSpace(validators[index]) >= amount) {
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
