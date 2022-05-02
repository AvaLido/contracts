// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/security/Pausable.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

import "./interfaces/IValidatorOracle.sol";
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
    // Errors
    error InvalidAddress();
    error InvalidQuorum();
    error InvalidValidatorId();
    error OracleMemberNotFound();
    error TooFewOracleMembers();
    error TooManyOracleMembers();

    // Events
	event OracleMemberAdded(address member);
    event OracleMemberRemoved(address member);
    event OracleQuorumChanged(uint256 QUORUM_THRESHOLD);
    event OracleReportSent(uint256 epochId, bytes32 hashedData);

    // State variables
    string[] public whitelistedValidators = ["1", "2", "3"]; // whitelisted Validator node ids. TODO: instantiate with a merkle tree? or read from a validator manager contract/AvaLido contract?
    address[] public oracleMembers = [0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC, 0xf195179eEaE3c8CAB499b5181721e5C57e4769b2]; // whitelisted addresses running our oracle daemon. TODO: instantiate with a merkle tree?
    address public AVALIDO; // address of the deployed Avalido contract
    uint256 public QUORUM_THRESHOLD; // the number of matching oracle reports required to submit information to the Oracle
    uint256 public constant MAX_MEMBERS = 3; // Maximum number of whitelisted oracle daemons. TODO: decide max; can we change it?
    uint256 internal constant MEMBER_NOT_FOUND = type(uint256).max; // index when oracle member does not exist in whitelist
    bool public isReported; // whether data has been pushed to the Oracle for the current reporting period

    // Mappings
    mapping(uint256 => mapping(bytes32 => uint256)) internal reportHashesByEpochId; // epochId => (hashOfOracleData => countofThisHash)
    mapping (uint256 => mapping(address => bool)) internal reportedOraclesByEpochId; // epochId => (oracleAddress => true/false)
    // when quorum is received for an epoch we can delete it from the mapping oracleMemberReports and set a mapping that the report is sent for this epoch?

    // Roles
    bytes32 internal constant ROLE_ORACLE_MANAGER = keccak256("ROLE_ORACLE_MANAGER"); // TODO: more granular roles for managing members, changing quorum, etc.

    // -------------------------------------------------------------------------
    //  Intilialization
    // -------------------------------------------------------------------------

    // /**
    // * @notice Initialize OracleManager contract, allowed to call only once
    // * @param _quorum inital quorum threshold
    // */
    // function initialize(
    //     string[3] calldata _whitelistedValidators,
    //     uint256 _quorum
    // ) external {
    //     // TODO: set up so it can be initialized only once
    //     // TODO: any checks needed on the validator list?
    //     if (_quorum == 0 || _quorum > MAX_MEMBERS) revert InvalidQuorum();

    //     //_setupRole(ROLE_ORACLE_MANAGER, msg.sender); // TODO: pass actual addresses for roles, not msg.sender
    //     whitelistedValidators = _whitelistedValidators;
    //     QUORUM_THRESHOLD = _quorum;
    // }

    // -------------------------------------------------------------------------
    //  Modifiers
    // -------------------------------------------------------------------------

    /**
     * @notice Allows function calls only from address with specific role.
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
     * @param _reportData Array of Validators.
     */
     // TODO: change _report back to Validator[]
    function receiveMemberReport(uint256 _epochId, string calldata _reportData) external whenNotPaused {
        uint256 index = _getOracleMemberId(msg.sender);
        if (index == MEMBER_NOT_FOUND) revert OracleMemberNotFound();

        // TODO: what if all validators have voted and no quorum has been reached? PANIC

        // 1. check if quorum has been reached and data sent to Oracle for this reporting period already; if yes, return
        // TODO: if (epochIsReported) return;

        // 2. check if the oracle member has already reported for the period; if yes, return, if no, log
        if (reportedOraclesByEpochId[_epochId][msg.sender]) {
            return;
        } else {
            reportedOraclesByEpochId[_epochId][msg.sender] = true;
        }

        // 3. Hash the incoming data: _report
        bytes32 hashedReportData = _hashReportData(_reportData);

        // 4. Calculate if the hash achieves quorum
        bool quorumReached = _calculateQuorum(_epochId, hashedReportData);

        // 5. store the hashed data count in reportHashesByEpochId
        _storeHashedDataCount(_epochId, hashedReportData);

        // 6. If quorum is achieved, commit the report to Oracle.sol
        if (quorumReached) {
            emit OracleReportSent(_epochId, hashedReportData);
        }
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
        return MEMBER_NOT_FOUND;
    }

    /**
     * @notice Find out whether an oracle member has submitted a report for a specific reporting period.
     * @param _epochId The id of the reporting epoch.
     * @param _oracleMember The address of the oracle member.
     * @return hasReported True or false.
     */
    function _hasOracleReported(uint256 _epochId, address _oracleMember) internal returns (bool) {
        return reportedOraclesByEpochId[_epochId][_oracleMember];
    }

    /**
     * @notice Hashes the report data from an oracle member.
     * @param _reportData An array of Validators.
     * @return hashedData The bytes32 hash of the data.
     */
     // TODO: change _reportData back to Validator[]
    function _hashReportData(string calldata _reportData) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(_reportData));
    }

    /**
     * @notice Retrieves the tally of a particular data hash for a particular reporting epoch.
     * @param _epochId The id of the reporting epoch.
     * @param _hashedData The keccak256 encoded hash of oracle members' reports.
     * @return count How many times the data hash has been recorded for the epoch.
     */
    function _retrieveHashedDataCount(uint256 _epochId, bytes32 _hashedData) internal view returns (uint256) {
        return reportHashesByEpochId[_epochId][_hashedData];
    }

    /**
     * @notice If quorum isn't reached when receiving a report, we increment the counter of this particular data hash for this epoch.
     * @param _epochId The id of the reporting epoch.
     * @param _hashedData The keccak256 encoded hash of the incoming oracle member's report.
     */
    function _storeHashedDataCount(uint256 _epochId, bytes32 _hashedData) internal {
        uint256 currentHashCount = _retrieveHashedDataCount(_epochId, _hashedData);
        uint256 newHashCount = currentHashCount + 1;
        reportHashesByEpochId[_epochId][_hashedData] = newHashCount;
    }

    /**
     * @notice Run each time a new oracle member report is received to calculate whether quorum has been reached for a reporting epoch.
     * @param _epochId The id of the reporting epoch.
     * @param _hashedData The keccak256 encoded hash of the incoming oracle member's report.
     * @return quorumReached True/false.
     */
    function _calculateQuorum(uint256 _epochId, bytes32 _hashedData) internal pure returns (bool) {
        // count = [eraId][dataHash]
    }

    // /**
    //  * @notice .
    //  * @param .
    //  * @param .
    //  * @return quorumThreshold.
    //  */
    // function _calculateQuorumThreshold(address[] calldata _oracleMembers) internal view returns (uint256) {
    //     // n = number of oracles
    //     // threshold = (n / 2)
    // }

    // /**
    //  * @notice Called when oracle members are added or removed from the whitelist to adjust the quorum threshold accordingly.
    //  * @param .
    //  */
    // function _setQuorumThreshold(address[] calldata _oracleMembers) internal () {
    //     // TODO: have an external function that calls this, restricted by the oracle manager role?
    // }

    // -------------------------------------------------------------------------
    //  Role-based functions
    // -------------------------------------------------------------------------

    /**
    * @notice Add `_oracleMember` from the oracleMembers whitelist, allowed to call only by ROLE_ORACLE_MANAGER
    * @param _oracleMember proposed member address
    */
    function addOracleMember(address _oracleMember) external {
        // TODO: add auth
        if (_oracleMember == address(0)) revert InvalidAddress();
        if (oracleMembers.length + 1 > MAX_MEMBERS) revert TooManyOracleMembers();
        // TODO: revert if oracle member already exists in whitelist

        oracleMembers.push(_oracleMember);
        emit OracleMemberAdded(_oracleMember);
    }

    /**
    * @notice Remove `_oracleMember` from the oracleMembers whitelist, allowed to call only by ROLE_ORACLE_MANAGER
    * @param _oracleMember proposed member address
    */
    function removeOracleMember(address _oracleMember) external {
        // TODO: add auth
        if (_oracleMember == address(0)) revert InvalidAddress();
        if (oracleMembers.length - 1 > QUORUM_THRESHOLD) revert TooFewOracleMembers();

        uint256 index = _getOracleMemberId(_oracleMember);
        if (index == MEMBER_NOT_FOUND) revert OracleMemberNotFound();

        uint256 last = oracleMembers.length - 1;
        if (index != last) oracleMembers[index] = oracleMembers[last];
        oracleMembers.pop();
        emit OracleMemberRemoved(_oracleMember);
    }

    // function pause

    // function resume

}
