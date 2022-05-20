// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "./interfaces/IValidatorSelector.sol";

contract FakeValidatorSelector is IValidatorSelector {

    string private _nodeID;
    constructor(
        string memory nodeID
    ) {
        _nodeID = nodeID;        
    }

    function selectValidatorsForStake(uint256 amount)
        public
        view
        returns (
            string[] memory,
            uint256[] memory,
            uint256
        )
    {
        
        uint256 remainingUnstaked = 0;
        
        uint256[] memory resultAmounts = new uint256[](1);
        resultAmounts[0] = amount;

        string[] memory validatorIds = new string[](1);
        validatorIds[0] = _nodeID;

        return (validatorIds, resultAmounts, remainingUnstaked);
    }
}
