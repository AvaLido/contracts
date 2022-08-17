// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import "./interfaces/IOracle.sol";
import "./Roles.sol";
import "./Types.sol";

/**
 * @title Lido on Avalanche Validator Oracle
 * @dev This contract stores finalized oracle reports from the OracleManager that have
 * achieved quorum. It does not do any oracle or validator-related management. It can only
 * be accessed by the OracleManager contract and ROLE_ORACLE_ADMIN.
 */
contract Oracle is IOracle, AccessControlEnumerable, Initializable {
    // Errors
    error EpochAlreadyFinalized();
    error InvalidAddress();
    error InvalidEpochDuration();
    error InvalidReportingEpoch();
    error OnlyOracleManagerContract();

    // Events
    event EpochDurationChanged(uint256 epochDuration);
    event OracleManagerAddressChanged(address newOracleManagerAddress);
    event OracleReportReceived(uint256 epochId);

    // State variables
    address public oracleManagerContract;
    uint256 public latestEpochId;
    uint256 public epochDuration; // in blocks

    // A list of all node IDs which is supplied periodically by our service.
    // We use this as a lookup table (by index) to nodeID, rather than having to write the IDs along side
    // our oracle report. This means we can store this expensive data on a lower frequency (e.g. once a week/month)
    // rather than on every report.
    string[] public validatorNodeIds;

    // Mappings
    mapping(uint256 => Validator[]) internal reportsByEpochId; // epochId => array of Validator[] structs

    function initialize(
        address _roleOracleAdmin,
        address _oracleManagerContract,
        uint256 _epochDuration
    ) public initializer {
        // Roles
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ROLE_ORACLE_ADMIN, _roleOracleAdmin);

        oracleManagerContract = _oracleManagerContract;
        epochDuration = _epochDuration;
    }

    // -------------------------------------------------------------------------
    //  Modifiers
    // -------------------------------------------------------------------------

    /**
     * @notice Allows function calls only from the OracleManager contract
     */
    modifier onlyOracleManagerContract() {
        if (msg.sender != oracleManagerContract) revert OnlyOracleManagerContract();
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
        // Check that we are not overwriting an already finalized epoch
        if (reportsByEpochId[_epochId].length != 0) revert EpochAlreadyFinalized();

        // Check that we are reporting for only the currently reportable epoch
        if (Oracle.nextReportableEpoch() != _epochId) revert InvalidReportingEpoch();

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
    function getLatestValidators() public view returns (Validator[] memory) {
        return reportsByEpochId[latestEpochId];
    }

    /**
     * @notice Get the nodeId by validator index.
     */
    function nodeIdByValidatorIndex(uint256 index) public view returns (string memory) {
        return validatorNodeIds[index];
    }

    /**
     * @notice Get the number of validators in the oracle.
     */
    function validatorCount() public view returns (uint256) {
        return validatorNodeIds.length;
    }

    /**
     * @notice Get all known validator nodeIds.
     */
    function allValidatorNodeIds() public view returns (string[] memory) {
        return validatorNodeIds;
    }

    /**
     * @notice Get next reportable epoch
     */
    function nextReportableEpoch() public view returns (uint256) {
        return latestEpochId + epochDuration;
    }

    // -------------------------------------------------------------------------
    //  Role-based functions
    // -------------------------------------------------------------------------

    /**
     * @notice Change address of the OracleManager contract, allowed to call only by ROLE_ORACLE_ADMIN
     * @param _oracleManagerAddress New OracleManager address.
     */
    function setOracleManagerAddress(address _oracleManagerAddress) external onlyRole(ROLE_ORACLE_ADMIN) {
        if (_oracleManagerAddress == address(0)) revert InvalidAddress();

        oracleManagerContract = _oracleManagerAddress;

        emit OracleManagerAddressChanged(_oracleManagerAddress);
    }

    function setNodeIDList(string[] calldata nodes) external onlyRole(ROLE_ORACLE_ADMIN) {
        delete validatorNodeIds;
        uint256 len = nodes.length;
        for (uint256 i = 0; i < len; i++) {
            validatorNodeIds.push(nodes[i]);
        }
        // Remove the latest epoch data because it will no longer be valid if node indicies
        // have changed. This will happen if validators are removed from the list.
        delete reportsByEpochId[latestEpochId];
    }

    function setEpochDuration(uint256 _epochDuration) external onlyRole(ROLE_ORACLE_ADMIN) {
        // Sanity check that epoch duration is at least greater than 0
        if (_epochDuration < 1) revert InvalidEpochDuration();

        epochDuration = _epochDuration;

        emit EpochDurationChanged(_epochDuration);
    }
}
