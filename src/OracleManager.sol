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
    event OracleQuorumChanged(uint8 QUORUM_THRESHOLD);
    // event OracleReportSent(uint256 reportingPeriod, string nodeId, ValidatorReportData reportData);

    // State variables
    string[] public whitelistedValidators = ["1", "2", "3"]; // whitelisted Validator node ids. TODO: instantiate with a merkle tree? or read from a validator manager contract/AvaLido contract?
    address[] public oracleMembers = [0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC, 0xf195179eEaE3c8CAB499b5181721e5C57e4769b2]; // whitelisted addresses running our oracle daemon. TODO: instantiate with a merkle tree?
    address public AVALIDO; // address of the deployed Avalido contract
    uint8 public QUORUM_THRESHOLD = 2; // the number of matching oracle reports required to submit information to the Oracle
    uint256 public constant MAX_MEMBERS = 3; // Maximum number of whitelisted oracle daemons. TODO: decide max; can we change it?
    uint256 internal constant MEMBER_NOT_FOUND = type(uint256).max; // index when oracle member does not exist in whitelist
    bool public isReported; // whether data has been pushed to the Oracle for the current reporting period

    // Mappings
    //mapping (aliceAddress => mapping (bobAddress => uint256)) approvals; // aliceAddress approves bobAddress to spend uint256
    mapping(address => string => ValidatorReportData[]) internal oracleMemberReports; // for each whitelisted validator we store each oracle member's OracleData report
    mapping (address => bool) internal receivedReports; // tracks if an oracle member has reported for the current reporting period
    // mapping (eraId => hashOfOracleData => countofThisHash)
    // when quorum is received for an epoch we can delete it from the mapping
    // separate mapping of whether a daemon has already reported for an era
    // mapping(epoch => daemonAddress => bool)
    hasReported = mapping[epoch][address]
    
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
    //     uint8 _quorum
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
     * @param _report Array of reports
     */
     // TODO: add eraId to the params
    function receiveMemberReport(ValidatorReportData[] calldata _report) external whenNotPaused {
        uint256 index = _getOracleMemberId(msg.sender);
        if (index == MEMBER_NOT_FOUND) revert OracleMemberNotFound();

        // TODO: what to do if report isn't for current reporting period?
        // TODO: check that msg.sender matches ValidatorReportData.oracleMember
        // TODO: what if all validators have voted and no quorum has been reached? PANIC

        // 1. check if quorum has been reached and data sent to Oracle for this reporting period already; if yes, return
        // if (isReported) return;

        // 2. check if the oracle member has already reported for the period; if yes, return
        if (receivedReports[msg.sender]) return;

        // 3. otherwise store the report
        uint256 arrayLength = _report.length;
        // for each node in the oracle's report...
        for (uint256 i = 0; i < arrayLength; ++i) {
            ValidatorReportData memory nodeReport = _report[i];
            string memory nodeId = nodeReport.nodeId;
            // ...push the ValidatorReportData to the correct nodeId in the oracleMemberReports mapping
            oracleMemberReports[nodeId].push(nodeReport);
            // ...and log that the oracle member has reported for this period
            receivedReports[msg.sender] = true;
        }

        // 4. calculate if quorum has now been reached and we can send the report to the Oracle
        // _calculateQuorum();

        // TODO: should we log an event for every oracle member's report for each reporting period?
    }

    // -------------------------------------------------------------------------
    //  Internal functions
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

    // /**
    // * @notice Return Validator node id index in the whitelist array
    // * @param _nodeId member address
    // * @return member index
    // */
    // function _getValidatorMemberId(string calldata _nodeId) internal view returns (uint256) {
    //     uint256 arrayLength = whitelistedValidators.length;
    //     for (uint256 i = 0; i < arrayLength; ++i) {
    //         if (whitelistedValidators[i] == _nodeId) {
    //             return i;
    //         }
    //     }
    //     return MEMBER_NOT_FOUND;
    // }

    /**
     * @notice Retrieves oracle member reports for a specific Validator node id.
     * @param _nodeId The Validator to retrive reports for.
     * @return reports Array of ValidatorReportData reports.
     */
    function _retrieveOracleMemberReports(string calldata _nodeId) internal returns (ValidatorReportData[] memory) {
        return oracleMemberReports[_nodeId];
    }

    // /**
    //  * @notice Calculates whether quorum has been reached for a Validator node.
    //  * @param _nodeId The Validator to calculate quorum for.
    //  * @return quorum True if quorum is reached; false if not.
    //  */
    // function _calculateQuorumForValidator(string calldata _nodeId) internal returns (bool) {
    //     // uint256 index = _getValidatorMemberId(_nodeId);
    //     if (index == MEMBER_NOT_FOUND) revert InvalidValidatorId();

    //     ValidatorReportData[] memory reportsForValidator = _retrieveOracleMemberReports(_nodeId);
    //     uint256 arrayLength = reportsForValidator.length;
    //     uint8 quorumCount = 0;

    //     // If not enough reports for quorum to be reached yet, return false
    //     if (arrayLength < QUORUM_THRESHOLD) return false;

    //     // If enough reports, iterate through and see if quorum has been reached
    //     // for (uint i = 0; i < arrayLength; i++) {

    //     // }
    // }

    /**
    * @notice Delete interim data for current reporting period
    */
    // function _clearReporting() internal {}

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

        // delete the data for the last eraId, let remained oracles report it again
        //_clearReporting();
    }

    // function pause

    // function resume

}
