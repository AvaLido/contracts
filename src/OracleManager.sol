// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/security/Pausable.sol";
import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import "./interfaces/IOracle.sol";
import "./Roles.sol";
import "./Types.sol";

uint256 constant INDEX_NOT_FOUND = type(uint256).max; // index when item is missing from array

/**
 * @title Lido on Avalanche Validator Oracle Manager
 * @dev This contract manages anything to do with the Validator oracle:
 * receiving reports from whitelisted oracle daemons; managing the whitelist
 * of oracle daemons; and finalising/writing reports to Oracle.sol so that
 * AvaLido.sol can read the latest P-chain state to calculate distribution
 * of stakes to our whitelisted Validators.
 */
contract OracleManager is Pausable, AccessControlEnumerable, Initializable {
    IOracle Oracle;

    // Errors
    error EpochAlreadyFinalized();
    error InvalidAddress();
    error InvalidQuorum();
    error InvalidReportingEpoch();
    error InvalidValidatorIndex();
    error OracleAlreadyReported();
    error OracleContractAddressNotSet();
    error OracleMemberExists();
    error OracleMemberNotFound();
    error ValidatorAlreadyWhitelisted();
    error ValidatorNodeIdNotFound();

    // Events
    event OracleAddressChanged(address oracleAddress);
    event OracleMemberAdded(address member);
    event OracleMemberRemoved(address member);
    event OracleReportSent(uint256 epochId);

    // State variables
    address[] public whitelistedOraclesArray; // whitelisted addresses running our oracle daemon.
    address public oracleContractAddress; // the deployed address

    // Mappings
    mapping(address => bool) public whitelistedOraclesMapping; // address => true if whitelisted
    mapping(uint256 => mapping(bytes32 => uint256)) internal reportHashesByEpochId; // epochId => (hashOfOracleData => countofThisHash)
    mapping(uint256 => mapping(address => bool)) public reportedOraclesByEpochId; // epochId => (oracleAddress => true/false)
    mapping(uint256 => bool) public finalizedReportsByEpochId; // epochId => true/false

    function initialize(
        address _roleOracleAdmin, // Role that can change whitelist of oracles.
        address[] memory _whitelistedOracleMembers // Whitelisted oracle member addresses.
    ) public initializer {
        // Roles
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ROLE_ORACLE_ADMIN, _roleOracleAdmin);

        // Set whitelist arrays
        whitelistedOraclesArray = _whitelistedOracleMembers;

        // Set whitelist mapping
        _addWhitelistedOraclesToMapping(_whitelistedOracleMembers);
    }

    // -------------------------------------------------------------------------
    //  Initialization
    // -------------------------------------------------------------------------

    /**
     * @notice Set the Oracle contract address that receives finalized reports.
     * @param _oracleAddress Oracle address
     */
    function setOracleAddress(address _oracleAddress) external onlyRole(ROLE_ORACLE_ADMIN) {
        oracleContractAddress = _oracleAddress;
        Oracle = IOracle(_oracleAddress);
        emit OracleAddressChanged(_oracleAddress);
    }

    function getOracleAddress() external view returns (address) {
        return oracleContractAddress;
    }

    function _addWhitelistedOraclesToMapping(address[] memory _whitelistedOracleMembers) internal {
        for (uint256 i = 0; i < _whitelistedOracleMembers.length; i++) {
            whitelistedOraclesMapping[_whitelistedOracleMembers[i]] = true;
        }
    }

    // -------------------------------------------------------------------------
    //  Public functions
    // -------------------------------------------------------------------------

    /**
     * @notice Called by daemons running our oracle service
     * @param _epochId The id of the reporting epoch.
     * @param _reportData Array of Validator structs.
     */
    function receiveMemberReport(uint256 _epochId, Validator[] calldata _reportData) external whenNotPaused {
        // 0. Check if Oracle deployed contract address is set
        if (oracleContractAddress == address(0)) revert OracleContractAddressNotSet();

        // Check if the reporting oracle is on our whitelist
        if (!_getOracleInWhitelistMapping(msg.sender)) revert OracleMemberNotFound();

        // Check if quorum has been reached and data sent to Oracle for this reporting period already; if yes, return
        if (finalizedReportsByEpochId[_epochId]) revert EpochAlreadyFinalized();

        // Check that we are reporting for a valid epoch
        if (!Oracle.isReportingEpochValid(_epochId)) revert InvalidReportingEpoch();

        // Check if the oracle member has already reported for the period; reverts if true
        if (reportedOraclesByEpochId[_epochId][msg.sender]) revert OracleAlreadyReported();

        // Check that the data only references indicies within the oracle list.
        uint256 numValidators = Oracle.validatorCount();
        if (numValidators == 0) {
            return;
        }
        for (uint256 i = 0; i < _reportData.length; i++) {
            uint256 index = ValidatorHelpers.getNodeIndex(_reportData[i]);
            if (index > numValidators - 1) {
                revert InvalidValidatorIndex();
            }
        }

        // Log that the oracle has reported for this epoch
        reportedOraclesByEpochId[_epochId][msg.sender] = true;

        // Hash the incoming data: _report
        bytes32 hashedReportData = _hashReportData(_reportData);

        // Store the hashed data count in reportHashesByEpochId
        _storeHashedDataCount(_epochId, hashedReportData);

        // Calculate if the hash achieves quorum
        bool quorumReached = _calculateQuorum(_epochId, hashedReportData);

        // If quorum is achieved, commit the report to Oracle.sol and log the epoch as finalized
        if (quorumReached) {
            finalizedReportsByEpochId[_epochId] = true;
            Oracle.receiveFinalizedReport(_epochId, _reportData);
            emit OracleReportSent(_epochId);
        }
    }

    // -------------------------------------------------------------------------
    //  Utils
    // -------------------------------------------------------------------------

    /**
     * @notice Return whether oracle member address exists in the whitelist
     * @param _oracleMember oracle member address
     * @return bool True or false
     */
    function _getOracleInWhitelistMapping(address _oracleMember) internal view returns (bool) {
        return whitelistedOraclesMapping[_oracleMember];
    }

    /**
     * @notice Hashes the report data from an oracle member.
     * @param _reportData An array of Validator structs.
     * @return hashedData The bytes32 hash of the data.
     */
    function _hashReportData(Validator[] calldata _reportData) internal pure returns (bytes32) {
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
        uint256 length = whitelistedOraclesArray.length;
        return (length / 2) + 1;
    }

    /**
     * @notice Returns array of whitelisted oracle addresses.
     * @return whitelistedOracles Array of oracles.
     */
    function getWhitelistedOracles() external view returns (address[] memory) {
        return whitelistedOraclesArray;
    }

    // -------------------------------------------------------------------------
    //  Whitelist management functions
    // -------------------------------------------------------------------------

    /**
     * @notice Return oracle member index in the whitelist array
     * @param _oracleMember oracle member address
     * @return index index
     */
    function _getOracleMemberIndex(address _oracleMember) internal view returns (uint256) {
        for (uint256 i = 0; i < whitelistedOraclesArray.length; ++i) {
            if (whitelistedOraclesArray[i] == _oracleMember) {
                return i;
            }
        }
        return INDEX_NOT_FOUND;
    }

    /**
     * @notice Add `_oracleMember` to the oracleMembers whitelist, allowed to be called only by ROLE_ORACLE_ADMIN
     * @param _oracleMember proposed oracle member address.
     */
    function addOracleMember(address _oracleMember) external onlyRole(ROLE_ORACLE_ADMIN) {
        if (_oracleMember == address(0)) revert InvalidAddress();
        if (_getOracleInWhitelistMapping(_oracleMember)) revert OracleMemberExists();

        // Add the oracle to our whitelist array
        whitelistedOraclesArray.push(_oracleMember);

        // Add the oracle to the whitelist mapping
        whitelistedOraclesMapping[_oracleMember] = true;

        emit OracleMemberAdded(_oracleMember);
    }

    /**
     * @notice Remove `_oracleMember` from the oracleMembers whitelist, allowed to be called only by ROLE_ORACLE_ADMIN
     * @param _oracleMember proposed oracle member address.
     */
    function removeOracleMember(address _oracleMember) external onlyRole(ROLE_ORACLE_ADMIN) {
        if (_oracleMember == address(0)) revert InvalidAddress();

        if (!_getOracleInWhitelistMapping(_oracleMember)) revert OracleMemberNotFound();

        // Delete the oracle from our whitelist array
        uint256 index = _getOracleMemberIndex(_oracleMember);
        uint256 last = whitelistedOraclesArray.length - 1;
        if (index != last) whitelistedOraclesArray[index] = whitelistedOraclesArray[last];
        whitelistedOraclesArray.pop();

        // Remove the oracle from the whitelist mapping
        delete whitelistedOraclesMapping[_oracleMember];
        emit OracleMemberRemoved(_oracleMember);
    }

    // -------------------------------------------------------------------------
    //  Contract management functions
    // -------------------------------------------------------------------------

    function pause() external onlyRole(ROLE_ORACLE_ADMIN) {
        _pause();
    }

    function resume() external onlyRole(ROLE_ORACLE_ADMIN) {
        _unpause();
    }
}
