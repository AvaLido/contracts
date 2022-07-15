// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/security/Pausable.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";
import "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

import "./interfaces/ITreasury.sol";

contract Treasury is Pausable, ReentrancyGuard, AccessControlEnumerable, ITreasury, Initializable {
    // Errors
    error AdminOnly();
    error AvaLidoOnly();
    error AlreadySet();
    address payable public avaLidoAddress;

    function initialize() public initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // -------------------------------------------------------------------------
    //  Admin functions
    // -------------------------------------------------------------------------

    function setAvaLidoAddress(address _address) external onlyAdmin {
        if (avaLidoAddress != address(0)) revert AlreadySet();
        avaLidoAddress = payable(_address);
    }

    function claim(uint256 amount) external onlyAvaLido {
        avaLidoAddress.transfer(amount);
    }

    
    // -------------------------------------------------------------------------
    //  Modifiers
    // -------------------------------------------------------------------------

    modifier onlyAdmin() {
        // TODO: Define proper RBAC. For now just use deployer as admin.
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert AdminOnly();
        _;
    }

    modifier onlyAvaLido() {
        if (msg.sender != avaLidoAddress) revert AvaLidoOnly();
        _;
    }
}

contract PrincipalTreasury is Treasury {}
contract RewardTreasury is Treasury {}
