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
    error InvalidAddress();
    error InvalidQuorum();
    error OracleMemberNotFound();
    //error TooFewOracleMembers();

    // Events
    event OracleMemberAdded(address member);
    event OracleMemberRemoved(address member);
    event OracleQuorumChanged(uint256 QUORUM_THRESHOLD);
    event OracleReportSent(uint256 indexed epochId, string indexed data);

    // State variables
    string[] public whitelistedValidators; // whitelisted Validator node ids. TODO: instantiate with a merkle tree? or read from a validator manager contract/AvaLido contract?
    address[] public oracleMembers; // whitelisted addresses running our oracle daemon. TODO: instantiate with a merkle tree?

    // Mappings
    mapping(uint256 => mapping(bytes32 => uint256)) internal reportHashesByEpochId; // epochId => (hashOfOracleData => countofThisHash)
    mapping(uint256 => mapping(address => bool)) internal reportedOraclesByEpochId; // epochId => (oracleAddress => true/false)
    // when quorum is received for an epoch we can delete it from the mapping oracleMemberReports and set a mapping that the report is sent for this epoch?

    // Roles
    bytes32 internal constant ROLE_ORACLE_MANAGER = keccak256("ROLE_ORACLE_MANAGER"); // TODO: more granular roles for managing members, changing quorum, etc.

    constructor(
        address _roleOracleManager, // Role that can change whitelist of oracles.
        string[] memory _whitelistedValidators, //Whitelist of validators we can stake with.
        address[] memory _oracleMembers // Whitelisted oracle member addresses.
    ) {
        // TODO: any checks needed on the validator list?

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
    }

    // -------------------------------------------------------------------------
    //  Public functions
    // -------------------------------------------------------------------------

    /**
     * @notice Called by daemons running our oracle service
     * @param _epochId The id of the reporting epoch.
     * @param _reportData Array of Validators.
     */
    // TODO: change _report back to Validator[]
    function receiveMemberReport(uint256 _epochId, string calldata _reportData)
        external
        whenNotPaused
        returns (string memory)
    {
        _getOracleMemberId(msg.sender);

        // 1. check if quorum has been reached and data sent to Oracle for this reporting period already; if yes, return
        // TODO: if (epochIsReported) return;

        // 2. check if the oracle member has already reported for the period; if yes, return, if no, log
        // if (_hasOracleReported(_epochId, msg.sender)) {
        //     return; // remove string
        // }

        reportedOraclesByEpochId[_epochId][msg.sender] = true;

        // 3. Hash the incoming data: _report
        bytes32 hashedReportData = _hashReportData(_reportData);

        // 5. store the hashed data count in reportHashesByEpochId
        _storeHashedDataCount(_epochId, hashedReportData);

        // 6. Calculate if the hash achieves quorum
        bool quorumReached = _calculateQuorum(_epochId, hashedReportData);

        // 6. If quorum is achieved, commit the report to Oracle.sol
        if (quorumReached) {
            console.log("Quorum reached");
            Oracle.receiveFinalizedReport(_epochId, _reportData);
            console.log("Report sent to Oracle");
            emit OracleReportSent(_epochId, _reportData);
        }

        return _reportData;
    }

    // -------------------------------------------------------------------------
    //  Internal functions/Utils
    // -------------------------------------------------------------------------

    /**
     * @notice Return oracle address index in the member array
     * @param _member oracle member address
     * @return member index
     */
    function _getOracleMemberId(address _member) internal view returns (uint256) {
        uint256 arrayLength = oracleMembers.length;
        for (uint256 i = 0; i < arrayLength; ++i) {
            if (oracleMembers[i] == _member) {
                return i;
            }
        }
        revert OracleMemberNotFound();
    }

    /**
     * @notice Find out whether an oracle member has submitted a report for a specific reporting period.
     * @param _epochId The id of the reporting epoch.
     * @param _oracleMember The address of the oracle member.
     * @return hasReported True or false.
     */
    function _hasOracleReported(uint256 _epochId, address _oracleMember) internal view returns (bool) {
        return reportedOraclesByEpochId[_epochId][_oracleMember];
    }

    /**
     * @notice Hashes the report data from an oracle member.
     * @param _reportData An array of Validators.
     * @return hashedData The bytes32 hash of the data.
     */
    // TODO: change _reportData back to Validator[]
    function _hashReportData(string calldata _reportData) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_reportData));
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
     * @notice Add `_oracleMember` from the oracleMembers whitelist, allowed to call only by ROLE_ORACLE_MANAGER
     * @param _oracleMember proposed oracle member address.
     */
    function addOracleMember(address _oracleMember) external onlyRole(ROLE_ORACLE_MANAGER) {
        if (_oracleMember == address(0)) revert InvalidAddress();
        // TODO: revert if oracle member already exists in whitelist

        oracleMembers.push(_oracleMember);
        emit OracleMemberAdded(_oracleMember);
    }

    /**
     * @notice Remove `_oracleMember` from the oracleMembers whitelist, allowed to call only by ROLE_ORACLE_MANAGER
     * @param _oracleMember proposed oracle member address.
     */
    function removeOracleMember(address _oracleMember) external onlyRole(ROLE_ORACLE_MANAGER) {
        if (_oracleMember == address(0)) revert InvalidAddress();
        // TODO: add checks for having too few oracle members. What should the minimum be?

        uint256 index = _getOracleMemberId(_oracleMember);

        uint256 last = oracleMembers.length - 1;
        if (index != last) oracleMembers[index] = oracleMembers[last];
        oracleMembers.pop();
        emit OracleMemberRemoved(_oracleMember);
    }

    // function pause

    // function resume

    // function changeRoleOracleManager
}
