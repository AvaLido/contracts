// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

import "./interfaces/IOracle.sol";
import "./Types.sol";

/**
 * @title Lido on Avalanche Validator Oracle
 * @dev This contract stores finalized oracle reports from the OracleManager that have
 * achieved quorum. It does not do any oracle or validator-related management. It can only
 * be accessed by the OracleManager contract and ROLE_ORACLE_MANAGER.
 */
contract Oracle is IOracle, AccessControlEnumerable {
    // Errors
    error InvalidAddress();
    error OnlyOracleManager();

    // Events
    event OracleManagerAddressChanged(address newOracleManagerAddress);
    event OracleReportReceived(uint256 epochId);
    // event RoleOracleManagerChanged(address newRoleOracleManager);

    // State variables
    address public ORACLE_MANAGER_CONTRACT;
    uint256 public latestEpochId;

    // Mappings
    mapping(uint256 => Validator[]) internal reportsByEpochId; // epochId => array of Validator[] structs

    // A list of all node IDs which is supplied periodically by our service.
    // We use this as a lookup table (by index) to nodeID, rather than having to write the IDs along side
    // our oracle report. This means we can store this expensive data on a lower frequency (e.g. once a week/month)
    // rather than on every report.
    string[] validatorNodeIds;

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
    //  OracleManager functions
    // -------------------------------------------------------------------------

    /**
     * @notice Called by OracleManager contract to store finalized report data.
     * @param _epochId The id of the reporting epoch.
     * @param _reportData Array Validator[] structs.
     */
    function receiveFinalizedReport(uint256 _epochId, Validator[] calldata _reportData) external onlyOracleManager {
        for (uint256 i = 0; i < _reportData.length; i++) {
            reportsByEpochId[_epochId].push(_reportData[i]);
        }
        if (_epochId > latestEpochId) {
            latestEpochId = _epochId;
        }
        emit OracleReportReceived(_epochId);
    }

    // -------------------------------------------------------------------------
    //  Public functions
    // -------------------------------------------------------------------------

    /**
     * @notice Get all finalized data for all validators for a specific epoch.
     * @param _epochId The id of the reporting epoch.
     * @return validatorData A struct of Validator data.
     */
    function getAllValidatorsByEpochId(uint256 _epochId) public view returns (Validator[] memory) {
        return reportsByEpochId[_epochId];
    }

    /**
     * @notice Get all finalized data for all validators for the latest epoch.
     */
    function getLatestValidator() public view returns (Validator[] memory) {
        return reportsByEpochId[latestEpochId];
    }

    function nodeIdByValidatorIndex(uint256 index) public view returns (string memory) {
        return validatorNodeIds[index];
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

    // TODO: Set validator list
    // Warning: When we update the list, indicies may change as validators are removed/added from avax.
    // This means that we need to ensure that we also clear out the latest epoch oracle data, becasue
    // that will be referencing old indicies.

    // TODO: function changeRoleOracleManager() {}
}
