// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

import "forge-std/console.sol";

import "./interfaces/IOracle.sol";
import "./Types.sol";

/**
 * @title Lido on Avalanche Validator Oracle
 * @dev This contract stores finalized oracle reports from the OracleManager that have
 * achieved quorum. It does not do any oracle or validator-related management. It can only
 * be accessed by the OracleManager contract and ROLE_ORACLE_MANAGER.
 */
contract Oracle is IOracle, AccessControlEnumerable, Initializable {
    // Errors
    error InvalidAddress();
    error OnlyOracleManagerContract();

    // Events
    event OracleManagerAddressChanged(address newOracleManagerAddress);
    event OracleReportReceived(uint256 epochId);
    // event RoleOracleManagerChanged(address newRoleOracleManager);

    // State variables
    address public ORACLE_MANAGER_CONTRACT;
    uint256 public latestEpochId;

    // A list of all node IDs which is supplied periodically by our service.
    // We use this as a lookup table (by index) to nodeID, rather than having to write the IDs along side
    // our oracle report. This means we can store this expensive data on a lower frequency (e.g. once a week/month)
    // rather than on every report.
    string[] validatorNodeIds;

    // Mappings
    mapping(uint256 => Validator[]) internal reportsByEpochId; // epochId => array of Validator[] structs

    // Roles
    bytes32 internal constant ROLE_ORACLE_MANAGER = keccak256("ROLE_ORACLE_MANAGER");

    function initialize(address _roleOracleManager, address _oracleManagerContract) public initializer {
        _setupRole(ROLE_ORACLE_MANAGER, _roleOracleManager);
        ORACLE_MANAGER_CONTRACT = _oracleManagerContract;
    }

    // -------------------------------------------------------------------------
    //  Modifiers
    // -------------------------------------------------------------------------

    /**
     * @notice Allows function calls only from the OracleManager contract
     */
    modifier onlyOracleManagerContract() {
        if (msg.sender != ORACLE_MANAGER_CONTRACT) revert OnlyOracleManagerContract();
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
    function receiveFinalizedReport(uint256 _epochId, Validator[] calldata _reportData)
        external
        onlyOracleManagerContract
    {
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

    /**
     * @notice Get the nodeId by validator index.
     */
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

    // TODO: function changeRoleOracleManager() {}

    function setNodeIDList(string[] calldata nodes) external onlyOracleManagerContract {
        delete validatorNodeIds;
        uint256 len = nodes.length;
        for (uint256 i = 0; i < len; i++) {
            validatorNodeIds[i] = nodes[i];
        }
        // Remove the latest epoch data becasue it will no longer be valid if node indicies
        // have changed. This will happen if validators are removed from the list.
        delete reportsByEpochId[latestEpochId];
    }
}
