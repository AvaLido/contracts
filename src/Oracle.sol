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
    event OracleReportReceived(uint256 epochId, bytes32 hashedData);
	event OracleManagerAddressChanged(address newOracleManagerAddress);

    // State variables
    address public ORACLE_MANAGER_CONTRACT;

    // Mappings
    mapping(uint256 => bytes32) internal reportHashesByEpochId; // epochId => hashOfOracleData

    // Roles
    bytes32 internal constant ROLE_ORACLE_MANAGER = keccak256("ROLE_ORACLE_MANAGER");

    // -------------------------------------------------------------------------
    //  Intilialization
    // -------------------------------------------------------------------------

    /**
    * @notice Initialize Oracle contract, allowed to call only once
    * @param _oracleManagerContract Address of the OracleManager contract
    */
    function initialize(address _oracleManagerContract) external {
        // TODO: set up so it can be initialized only once

        //_setupRole(ROLE_ORACLE_MANAGER, msg.sender); // TODO: pass actual addresses for roles, not msg.sender
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

	/**
     * @notice Allows function calls only from address with specific role.
	 * @param role Keccak256 hash of the role string.
     */
    modifier auth(bytes32 role) {
        require(hasRole(role, msg.sender), "Unauthorized role for this function.");
        _;
    }

    // -------------------------------------------------------------------------
    //  Public functions
    // -------------------------------------------------------------------------

    /**
     * @notice Called by daemons running our oracle service 
	 * @param _epochId The id of the reporting epoch.
     * @param _hashedReportData The hash of the Validators[] data.
     */
    function receiveFinalizedReport(uint256 _epochId, bytes32 _hashedReportData) external onlyOracleManager {
		reportHashesByEpochId[_epochId] = _hashedReportData;
    	emit OracleReportReceived(_epochId, _hashedReportData);
    }

	/**
    * @notice Called by AvaLido to retrieve finalized data for a validator for a specific reporting epoch.
    * @param _epochId The id of the reporting epoch.
	* @param _nodeId The id of the validator node.
    * @return validatorData A struct of Validator data.
    */
	// TODO: change return back to Validator
    function getValidatorDataByEpochId(uint256 _epochId, string calldata _nodeId) public view returns (bytes32) {
		console.log('In getValidatorDataByEpochId');
		// TODO: process data and find Validator struct in array
		// TODO: unhash data
		return reportHashesByEpochId[_epochId];
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
    function changeOracleManagerAddress(address _newOracleManagerAddress) external auth(ROLE_ORACLE_MANAGER) {
        if (_newOracleManagerAddress == address(0)) revert InvalidAddress();

		ORACLE_MANAGER_CONTRACT = _newOracleManagerAddress;

        emit OracleManagerAddressChanged(_newOracleManagerAddress);
    }
}
