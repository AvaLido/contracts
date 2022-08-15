// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import "./interfaces/ITreasury.sol";

contract Treasury is ITreasury {
    // Errors
    error InvalidAddress();
    error AvaLidoOnly();
    address payable public avaLidoAddress;

    constructor(address _avaLidoAddress) {
        avaLidoAddress = payable(_avaLidoAddress);
    }

    function claim(uint256 amount) external onlyAvaLido {
        avaLidoAddress.transfer(amount);
    }

    modifier onlyAvaLido() {
        if (msg.sender != avaLidoAddress) revert AvaLidoOnly();
        _;
    }
}
