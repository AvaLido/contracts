// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import "./interfaces/ITreasury.sol";

contract Treasury is ITreasury {
    // Errors
    error InvalidAddress();
    error BeneficiaryOnly();
    address payable public beneficiaryAddress;

    constructor(address _beneficiaryAddress) {
        beneficiaryAddress = payable(_beneficiaryAddress);
    }

    function claim(uint256 amount) external onlyBeneficiary {
        beneficiaryAddress.transfer(amount);
    }

    modifier onlyBeneficiary() {
        if (msg.sender != beneficiaryAddress) revert BeneficiaryOnly();
        _;
    }
}
