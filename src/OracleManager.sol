// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/security/Pausable.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

import "./test/console.sol";

import "./interfaces/IOracle.sol";
import "./Types.sol";

/**
 * @title Lido on Avalanche Validator Oracle Manager
 * @dev This contract manages anything to do with the Validator oracle:
 * receiving reports from whitelisted oracle daemons; managing the whitelist
 * of oracle daemons; and finalising/writing reports to Oracle.sol so that
 * AvaLido.sol can read the latest P-chain state to calculate distribution
 * of stakes to our whitelisted Validators.
 */

contract OracleManager is Pausable, ReentrancyGuard, AccessControlEnumerable {
    IOracle Oracle;

    // Errors
    error EpochAlreadyFinalized();
    error InvalidAddress();
    error InvalidQuorum();
    error OracleAlreadyReported();
    error OracleMemberExists();
    error OracleMemberNotFound();
    //error TooFewOracleMembers();
    error ValidatorAlreadyWhitelisted();
    error ValidatorNodeIdNotFound();

    // Events
    event OracleAddressChanged(address oracleAddress);
    event OracleMemberAdded(address member);
    event OracleMemberRemoved(address member);
    event OracleReportSent(uint256 epochId);
    // event RoleOracleManagerChanged(address newRoleOracleManager);
    event WhitelistedValidatorAdded(string nodeId);
    event WhitelistedValidatorRemoved(string nodeId);

    // State variables
    string[] public whitelistedValidators; // whitelisted Validator node ids. TODO: instantiate with a merkle tree? or read from a validator manager contract/AvaLido contract?
    address[] public oracleMembers; // whitelisted addresses running our oracle daemon. TODO: instantiate with a merkle tree?

    uint256 internal constant INDEX_NOT_FOUND = type(uint256).max; // index when item is missing from array

    // Mappings
    mapping(uint256 => mapping(bytes32 => uint256)) internal reportHashesByEpochId; // epochId => (hashOfOracleData => countofThisHash)
    mapping(uint256 => mapping(address => bool)) internal reportedOraclesByEpochId; // epochId => (oracleAddress => true/false)
    mapping(uint256 => bool) internal finalizedReportsByEpochId; // epochId => true/false
    // when quorum is received for an epoch we can delete it from the mapping oracleMemberReports

    // Roles
    bytes32 internal constant ROLE_ORACLE_MANAGER = keccak256("ROLE_ORACLE_MANAGER"); // TODO: more granular roles for managing members, changing quorum, etc.

    constructor(
        address _roleOracleManager, // Role that can change whitelist of oracles.
        string[] memory _whitelistedValidators, //Whitelist of validators we can stake with.
        address[] memory _oracleMembers // Whitelisted oracle member addresses.
    ) {
        _setupRole(ROLE_ORACLE_MANAGER, _roleOracleManager);
        whitelistedValidators = _whitelistedValidators;
        oracleMembers = _oracleMembers;
    }

    // -------------------------------------------------------------------------
    //  Initialization
    // -------------------------------------------------------------------------

    /**
     * @notice Set the Oracle contract address that receives finalized reports.
     * @param _oracleAddress Oracle address
     */
    function setOracleAddress(address _oracleAddress) external onlyRole(ROLE_ORACLE_MANAGER) {
        Oracle = IOracle(_oracleAddress);
        emit OracleAddressChanged(_oracleAddress);
    }

    // -------------------------------------------------------------------------
    //  Public functions
    // -------------------------------------------------------------------------

    /**
     * @notice Called by daemons running our oracle service
     * @param _epochId The id of the reporting epoch.
     * @param _reportData Array of ValidatorData structs.
     */
    function receiveMemberReport(uint256 _epochId, ValidatorData[] calldata _reportData) external whenNotPaused {
        // 1. Check if the reporting oracle is on our whitelist
        if (_getOracleMemberIndex(msg.sender) == INDEX_NOT_FOUND) revert OracleMemberNotFound();

        // 2. Check if quorum has been reached and data sent to Oracle for this reporting period already; if yes, return
        if (finalizedReportsByEpochId[_epochId]) revert EpochAlreadyFinalized();

        // 3. Check if the oracle member has already reported for the period; reverts if true
        if (reportedOraclesByEpochId[_epochId][msg.sender]) revert OracleAlreadyReported();

        // 4. Check that the data only includes whitelisted validators
        bool reportContainsOnlyWhitelistedValidators = _reportContainsOnlyWhitelistedValidators(_reportData);
        if (!reportContainsOnlyWhitelistedValidators) revert ValidatorNodeIdNotFound();

        // 5. Log that the oracle has reported for this epoch
        reportedOraclesByEpochId[_epochId][msg.sender] = true;

        // 6. Hash the incoming data: _report
        bytes32 hashedReportData = _hashReportData(_reportData);

        // 7. Store the hashed data count in reportHashesByEpochId
        _storeHashedDataCount(_epochId, hashedReportData);

        // 8. Calculate if the hash achieves quorum
        bool quorumReached = _calculateQuorum(_epochId, hashedReportData);

        // 9. If quorum is achieved, commit the report to Oracle.sol and log the epoch as finalized
        if (quorumReached) {
            finalizedReportsByEpochId[_epochId] = true;
            Oracle.receiveFinalizedReport(_epochId, _reportData);
            emit OracleReportSent(_epochId);
        }
    }

    // -------------------------------------------------------------------------
    //  Internal functions/Utils
    // -------------------------------------------------------------------------

    /**
     * @notice Return oracle address index in the member array
     * @param _member oracle member address
     * @return index index
     */
    function _getOracleMemberIndex(address _member) internal view returns (uint256) {
        for (uint256 i = 0; i < oracleMembers.length; ++i) {
            if (oracleMembers[i] == _member) {
                return i;
            }
        }
        return INDEX_NOT_FOUND;
    }

    /**
     * @notice Return node id index in the whitelisted validator array
     * @param _nodeId validator node id
     * @return index index
     */
    function _getWhitelistedValidatorIndex(string calldata _nodeId) internal view returns (uint256) {
        for (uint256 i = 0; i < whitelistedValidators.length; ++i) {
            if (keccak256(abi.encodePacked(whitelistedValidators[i])) == keccak256(abi.encodePacked(_nodeId))) {
                return i;
            }
        }
        return INDEX_NOT_FOUND;
    }

    /**
     * @notice Iterates over whitelisted validator array and checks
     * @param
     * @return
     */
    function _reportContainsOnlyWhitelistedValidators(ValidatorData[] calldata _reportData)
        internal
        view
        returns (bool)
    {
        for (uint256 i = 0; i < _reportData.length; i++) {
            uint256 nodeId = _getWhitelistedValidatorIndex(_reportData[i].nodeId);
            if (nodeId == INDEX_NOT_FOUND) {
                return false;
            }
        }
        return true;
    }

    /**
     * @notice Hashes the report data from an oracle member.
     * @param _reportData An array of ValidatorData structs.
     * @return hashedData The bytes32 hash of the data.
     */
    function _hashReportData(ValidatorData[] calldata _reportData) internal pure returns (bytes32) {
        return keccak256(abi.encode(_reportData));
    }

    /**
     * @notice Retrieves the tally of a particular data hash for a particular reporting epoch.
     * @param _epochId The id of the reporting epoch.
     * @param _hashedData The keccak256 encoded hash of oracle members' reports.
     * @return count How many times the data hash has been recorded for the epoch.
     */
    function retrieveHashedDataCount(uint256 _epochId, bytes32 _hashedData) public view returns (uint256) {
        return reportHashesByEpochId[_epochId][_hashedData];
    }

    /**
     * @notice If quorum isn't reached when receiving a report, we increment the counter of this particular data hash for this epoch.
     * @param _epochId The id of the reporting epoch.
     * @param _hashedData The keccak256 encoded hash of the incoming oracle member's report.
     */
    function _storeHashedDataCount(uint256 _epochId, bytes32 _hashedData) internal {
        reportHashesByEpochId[_epochId][_hashedData]++;
    }

    /**
     * @notice Run each time a new oracle member report is received to calculate whether quorum has been reached for a reporting epoch.
     * @param _epochId The id of the reporting epoch.
     * @param _hashedData The keccak256 encoded hash of the incoming oracle member's report.
     * @return quorumReached True/false.
     */
    function _calculateQuorum(uint256 _epochId, bytes32 _hashedData) internal view returns (bool) {
        uint256 currentHashCount = retrieveHashedDataCount(_epochId, _hashedData);
        uint256 quorumThreshold = _calculateQuorumThreshold();
        return currentHashCount >= quorumThreshold;
    }

    /**
     * @notice Calculates the current quorum threshold based on the number of oracle members.
     * @dev In Solidity all division rounds down to the nearest integer, so using n / 2 works whether
     * the length of the oracle members list is even or odd - quorum is always (n / 2) + 1.
     * @return quorumThreshold The current quorum threshold.
     */
    function _calculateQuorumThreshold() internal view returns (uint256) {
        uint256 length = oracleMembers.length;
        return (length / 2) + 1;
    }

    // -------------------------------------------------------------------------
    //  Role-based functions
    // -------------------------------------------------------------------------

    /**
     * @notice Add `_oracleMember` to the oracleMembers whitelist, allowed to be called only by ROLE_ORACLE_MANAGER
     * @param _oracleMember proposed oracle member address.
     */
    function addOracleMember(address _oracleMember) external onlyRole(ROLE_ORACLE_MANAGER) {
        if (_oracleMember == address(0)) revert InvalidAddress();
        if (_getOracleMemberIndex(_oracleMember) != INDEX_NOT_FOUND) revert OracleMemberExists();

        oracleMembers.push(_oracleMember);
        emit OracleMemberAdded(_oracleMember);
    }

    /**
     * @notice Remove `_oracleMember` from the oracleMembers whitelist, allowed to be called only by ROLE_ORACLE_MANAGER
     * @param _oracleMember proposed oracle member address.
     */
    function removeOracleMember(address _oracleMember) external onlyRole(ROLE_ORACLE_MANAGER) {
        if (_oracleMember == address(0)) revert InvalidAddress();
        // TODO: add checks for having too few oracle members. What should the minimum be?

        uint256 index = _getOracleMemberIndex(_oracleMember);
        if (index == INDEX_NOT_FOUND) revert OracleMemberNotFound();

        uint256 last = oracleMembers.length - 1;
        if (index != last) oracleMembers[index] = oracleMembers[last];
        oracleMembers.pop();
        emit OracleMemberRemoved(_oracleMember);
    }

    /**
     * @notice Add `_nodeId` to the validator whitelist, allowed to be called only by ROLE_ORACLE_MANAGER
     * @param _nodeId proposed validator node id.
     */
    function addWhitelistedValidator(string calldata _nodeId) external onlyRole(ROLE_ORACLE_MANAGER) {
        if (_getWhitelistedValidatorIndex(_nodeId) != INDEX_NOT_FOUND) revert ValidatorAlreadyWhitelisted();

        whitelistedValidators.push(_nodeId);
        emit WhitelistedValidatorAdded(_nodeId);
    }

    /**
     * @notice Remove `_nodeId` from the validator whitelist, allowed to be called only by ROLE_ORACLE_MANAGER
     * @param _nodeId proposed validator node id.
     */
    function removeWhitelistedValidator(string calldata _nodeId) external onlyRole(ROLE_ORACLE_MANAGER) {
        uint256 index = _getWhitelistedValidatorIndex(_nodeId);
        if (index == INDEX_NOT_FOUND) revert ValidatorNodeIdNotFound();

        uint256 last = whitelistedValidators.length - 1;
        if (index != last) whitelistedValidators[index] = whitelistedValidators[last];
        whitelistedValidators.pop();
        emit WhitelistedValidatorRemoved(_nodeId);
    }

    function pause() external onlyRole(ROLE_ORACLE_MANAGER) {
        _pause();
    }

    function resume() external onlyRole(ROLE_ORACLE_MANAGER) {
        _unpause();
    }

    // TODO: function changeRoleOracleManager() {}
}
