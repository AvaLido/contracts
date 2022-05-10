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
    event OracleReportReceived(uint256 epochId, string data);
    event OracleManagerAddressChanged(address newOracleManagerAddress);

    // State variables
    address public ORACLE_MANAGER_CONTRACT;

    // Mappings
    mapping(uint256 => string) internal reportsByEpochId; // epochId => hashOfOracleData

    // Roles
    bytes32 internal constant ROLE_ORACLE_MANAGER = keccak256("ROLE_ORACLE_MANAGER");

    constructor(address _oracleManagerContract) {
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
     * @param _reportData The Validators[] data.
     */
    function receiveFinalizedReport(uint256 _epochId, string calldata _reportData) external onlyOracleManager {
        reportsByEpochId[_epochId] = _reportData;
        emit OracleReportReceived(_epochId, _reportData);
    }

    /**
     * @notice Called by AvaLido to retrieve finalized data for a validator for a specific reporting epoch.
     * @param _epochId The id of the reporting epoch.
     * @param _nodeId The id of the validator node.
     * @return validatorData A struct of Validator data.
     */
    // TODO: change return back to Validator
    function getValidatorDataByEpochId(uint256 _epochId, string calldata _nodeId) public view returns (string memory) {
        console.log("In getValidatorDataByEpochId");
        // TODO: process data and find Validator struct in array
        // TODO: unhash data
        return reportsByEpochId[_epochId];
    }

    // -------------------------------------------------------------------------
    //  Internal functions/Utils
    // -------------------------------------------------------------------------

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
}
