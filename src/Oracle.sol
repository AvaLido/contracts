// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";

import "./test/console.sol";

import "./interfaces/IValidatorOracle.sol";
import "./Types.sol";

/**
 * @title Lido on Avalanche Validator Oracle
 * @dev This contract only stores finalized oracle reports from the OracleManager that have
 achieved quorum. It does not do any oracle or validator-related management. It can only
 * be accessed by the OracleManager contract and ROLE_ORACLE_MANAGER.
 */

contract Oracle is AccessControlEnumerable {
    // Errors
    error InvalidAddress();
    error OnlyOracleManager();

    // Events
    event OracleManagerAddressChanged(address newOracleManagerAddress);
    event OracleReportReceived(uint256 epochId);
    // event RoleOracleManagerChanged(address newRoleOracleManager);

    // State variables
    address public ORACLE_MANAGER_CONTRACT;

    // Mappings
    mapping(uint256 => ValidatorData[]) internal reportsByEpochId; // epochId => array of ValidatorData[] structs

    // Roles
    bytes32 internal constant ROLE_ORACLE_MANAGER = keccak256("ROLE_ORACLE_MANAGER");

    constructor(address _roleOracleManager, address _oracleManagerContract) {
        _setupRole(ROLE_ORACLE_MANAGER, _roleOracleManager);
        ORACLE_MANAGER_CONTRACT = _oracleManagerContract;
    }

    // -------------------------------------------------------------------------
    //  Modifiers
    // -------------------------------------------------------------------------

    /**
     * @notice Allows function calls only from the OracleManager contract
     */
    modifier onlyOracleManager() {
        if (msg.sender != ORACLE_MANAGER_CONTRACT) revert OnlyOracleManager();
        _;
    }

    // -------------------------------------------------------------------------
    //  Public functions
    // -------------------------------------------------------------------------

    /**
     * @notice Called by OracleManager contract to store finalized report data.
     * @param _epochId The id of the reporting epoch.
     * @param _reportData Array ValidatorData[] structs.
     */
    function receiveFinalizedReport(uint256 _epochId, ValidatorData[] calldata _reportData) external onlyOracleManager {
        for (uint256 i = 0; i < _reportData.length; i++) {
            reportsByEpochId[_epochId].push(_reportData[i]);
        }
        emit OracleReportReceived(_epochId);
    }

    /**
     * @notice Called by AvaLido to retrieve finalized data for all validators for a specific reporting epoch.
     * @param _epochId The id of the reporting epoch.
     * @return validatorData A struct of Validator data.
     */
    function getAllValidatorDataByEpochId(uint256 _epochId) public view returns (ValidatorData[] memory) {
        return reportsByEpochId[_epochId];
    }

    // -------------------------------------------------------------------------
    //  Role-based functions
    // -------------------------------------------------------------------------

    /**
     * @notice Change address of the OracleManager contract, allowed to call only by ROLE_ORACLE_MANAGER
     * @param _newOracleManagerAddress Proposed new OracleManager address.
     */
    function changeOracleManagerAddress(address _newOracleManagerAddress) external onlyRole(ROLE_ORACLE_MANAGER) {
        if (_newOracleManagerAddress == address(0)) revert InvalidAddress();

        ORACLE_MANAGER_CONTRACT = _newOracleManagerAddress;

        emit OracleManagerAddressChanged(_newOracleManagerAddress);
    }

    // TODO: function changeRoleOracleManager() {}
}
