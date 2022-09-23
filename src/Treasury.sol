// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import "./interfaces/ITreasury.sol";
import "./interfaces/ITreasuryBeneficiary.sol";

contract Treasury is ITreasury {
    // Errors
    error InvalidAddress();
    error BeneficiaryOnly();
    ITreasuryBeneficiary public beneficiary;

    constructor(address _beneficiaryAddress) {
        beneficiary = ITreasuryBeneficiary(_beneficiaryAddress);
    }

    receive() external payable {}

    function claim(uint256 amount) external onlyBeneficiary {
        beneficiary.receiveFund{value: amount}();
    }

    modifier onlyBeneficiary() {
        if (msg.sender != address(beneficiary)) revert BeneficiaryOnly();
        _;
    }
}
