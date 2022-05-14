// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

interface IValidatorSelector {
    /**
     * @dev Returns an array of nodeIds, amount to allocate to each node, and a remaining unalloacted amount.
     */
    function selectValidatorsForStake(uint256 amount)
        external
        view
        returns (
            string[] memory,
            uint256[] memory,
            uint256
        );
}
