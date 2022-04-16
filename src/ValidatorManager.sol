// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";

import "./ValidatorOracle";

contract ValidatorManager is AccessControlEnumerable {
    // error DuplicateValidator();
    // error UnknownValidator();

    enum SelectionStrategy {
        Allowlist,
        Blocklist
    }

    SelectionStrategy strategy = SelectionStrategy.Allowlist;
    mapping(string => bool) validatorListSet;

    ValidatorOracle vOracle;

    constructor(address oracleAddress) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        vOracle = ValidatorOracle(oracleAddress);
    }

    modifier onlyAdmin() {
        hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _;
    }

    function setSelectionStrategy(SelectionStrategy strat) public onlyAdmin {
        strategy = strat;
        delete validatorIds;
    }

    function addValidatorToList(string memory validatorId) public onlyAdmin {
        validatorListSet[validatorId] = true;
    }

    function removeValidatorFromList(string memory validatorId) public onlyAdmin {
        delete validatorListSet[validatorId];
    }

    function selectValidatorsForStake(uint256 amount) public view returns (string[] memory, uint256[] memory) {
        // if (amount == 0) return (string[], uint256[]);
        ValidatorOracle.Validator[] validators = vOracle.getAvailableValidatorsWithCapacity();
        if (strategy == SelectionStrategy.Allowlist) {}

        return ([], []);
    }

    function filterByAllowlist(ValidatorOracle.Validator[] memory validators, string[] memory allowList)
        returns (string[] memory)
    {
        return [];
    }
}
