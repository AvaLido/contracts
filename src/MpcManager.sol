// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/security/Pausable.sol";
import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import "./Roles.sol";
import "./interfaces/IMpcManager.sol";

contract MpcManager is Pausable, AccessControlEnumerable, IMpcManager, Initializable {
    uint256 constant MAX_GROUP_SIZE = 255;
    // Errors
    error AvaLidoOnly();

    error InvalidGroupSize(); // A group requires 2 or more participants.
    error InvalidThreshold(); // Threshold has to be in range [1, n - 1].
    error GroupNotFound();
    error InvalidGroupMembership();
    error AttemptToReaddGroup();

    error KeyNotGenerated();
    error KeyNotFound();
    error AttemptToReconfirmKey();

    error InvalidAmount();
    error RequestNotFound();
    error QuorumAlreadyReached();
    error AttemptToRejoin();
    error Unrecognized();

    // Events
    event ParticipantAdded(bytes indexed publicKey, bytes32 groupId, uint256 index);
    event KeyGenerated(bytes32 indexed groupId, bytes publicKey);
    event KeygenRequestAdded(bytes32 indexed groupId);
    event StakeRequestAdded(
        uint256 requestId,
        bytes indexed publicKey,
        string nodeID,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    );
    event StakeRequestStarted(
        uint256 requestId,
        bytes indexed publicKey,
        uint256 participantIndices,
        string nodeID,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    );

    event ExportUTXORequest(
        bytes32 txId,
        uint32 outputIndex,
        address to,
        bytes indexed genPubKey,
        uint256[] participantIndices
    );

    // Types
    enum RequestStatus {
        UNKNOWN,
        STARTED,
        COMPLETED
    }
    enum RequestType {
        UNKNOWN,
        STAKE
    }
    enum UTXOutputIndex {
        PRINCIPAL, // 0 in Avalanche network
        REWARD // 1 in Avalanche network
    }

    struct ParticipantInfo {
        bytes publicKey;
        address ethAddress;
    }

    // Other request types to be added: e.g. REWARD, PRINCIPAL, RESTAKE
    struct Request {
        bytes publicKey;
        RequestType requestType;
        uint256 participantIndices;
        uint256 confirmedCount;
        RequestStatus status;
    }
    struct StakeRequestDetails {
        string nodeID;
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
    }

    // State variables
    bytes public lastGenPubKey;
    address public lastGenAddress;

    address public avaLidoAddress;
    address public principalTreasuryAddress;
    address public rewardTreasuryAddress;

    // groupId -> number of participants in the group
    mapping(bytes32 => uint256) private _groupParticipantCount;
    // groupId -> threshold
    mapping(bytes32 => uint256) private _groupThreshold;
    // groupId -> index -> participant
    mapping(bytes32 => mapping(uint256 => ParticipantInfo)) private _groupParticipants;

    // key -> groupId
    mapping(bytes => KeyInfo) private _generatedKeys;

    // key -> index -> confirmed
    mapping(bytes => mapping(uint256 => bool)) private _keyConfirmations;

    // request status
    mapping(uint256 => Request) private _requests;
    mapping(uint256 => StakeRequestDetails) private _stakeRequestDetails;
    uint256 private _lastRequestId;

    // utxoTxId -> utxoIndex -> joinExportUTXOParticipantIndices
    mapping(bytes32 => mapping(uint32 => uint256[])) private _joinExportUTXOParticipantIndices;

    function initialize(
        address _roleMpcAdmin, // Role that can add mpc group and request for keygen.
        address _avaLidoAddress,
        address _principalTreasuryAddress,
        address _rewardTreasuryAddress
    ) public initializer {
        _setupRole(ROLE_MPC_MANAGER, _roleMpcAdmin);
        avaLidoAddress = _avaLidoAddress;
        principalTreasuryAddress = _principalTreasuryAddress;
        rewardTreasuryAddress = _rewardTreasuryAddress;
    }

    // -------------------------------------------------------------------------
    //  External functions
    // -------------------------------------------------------------------------

    /**
     * @notice Send AVAX and start a StakeRequest.
     * @dev The received token will be immediately forwarded the the last generated MPC wallet
     * and the group members will handle the stake flow from the c-chain to the p-chain.
     */
    function requestStake(
        string calldata nodeID,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    ) external payable onlyAvaLido {
        if (lastGenAddress == address(0)) revert KeyNotGenerated();
        if (msg.value != amount) revert InvalidAmount();
        payable(lastGenAddress).transfer(amount);
        _handleStakeRequest(lastGenPubKey, nodeID, amount, startTime, endTime);
    }

    /**
     * @notice Admin will call this function to create an MPC group consisting of n members
     * and a specified threshold t. The signing can be performed by any t + 1 participants
     * from the group.
     * @param publicKeys The public keys which identify the n group members.
     * @param threshold The threshold t. Note: t + 1 participants are required to complete a
     * signing.
     */
    function createGroup(bytes[] calldata publicKeys, uint256 threshold) external onlyRole(ROLE_MPC_MANAGER) {
        // TODO: Refine ACL
        // TODO: Check public keys are valid
        if (publicKeys.length < 2) revert InvalidGroupSize();
        if (threshold < 1 || threshold >= publicKeys.length) revert InvalidThreshold();

        bytes memory b = bytes.concat(bytes32(threshold));
        for (uint256 i = 0; i < publicKeys.length; i++) {
            b = bytes.concat(b, publicKeys[i]);
        }
        bytes32 groupId = keccak256(b);

        uint256 count = _groupParticipantCount[groupId];
        if (count > 0) revert AttemptToReaddGroup();
        _groupParticipantCount[groupId] = publicKeys.length;
        _groupThreshold[groupId] = threshold;

        for (uint256 i = 0; i < publicKeys.length; i++) {
            _groupParticipants[groupId][i + 1].publicKey = publicKeys[i]; // Participant index is 1-based.
            _groupParticipants[groupId][i + 1].ethAddress = _calculateAddress(publicKeys[i]); // Participant index is 1-based.
            emit ParticipantAdded(publicKeys[i], groupId, i + 1);
        }
    }

    /**
     * @notice Admin will call this function to tell the group members to generate a key. Multiple
     * keys can be generated for the same group.
     * @param groupId The id of the group which is deterministically derived from the public keys
     * of the ordered group members and the threshold.
     */
    function requestKeygen(bytes32 groupId) external onlyRole(ROLE_MPC_MANAGER) {
        // TODO: Refine ACL
        emit KeygenRequestAdded(groupId);
    }

    /**
     * @notice All group members have to report the generated key which also serves as the proof.
     * @param groupId The id of the mpc group.
     * @param myIndex The index of the participant in the group. This is 1-based.
     * @param generatedPublicKey The generated public key.
     */
    function reportGeneratedKey(
        bytes32 groupId,
        uint256 myIndex,
        bytes calldata generatedPublicKey
    ) external onlyGroupMember(groupId, myIndex) {
        KeyInfo storage info = _generatedKeys[generatedPublicKey];

        if (info.confirmed) revert AttemptToReconfirmKey();

        // TODO: Check public key valid
        _keyConfirmations[generatedPublicKey][myIndex] = true;

        if (_generatedKeyConfirmedByAll(groupId, generatedPublicKey)) {
            info.groupId = groupId;
            info.confirmed = true;
            // TODO: The two sentence below for naive testing purpose, to deal with them furher.
            lastGenPubKey = generatedPublicKey;
            lastGenAddress = _calculateAddress(generatedPublicKey);
            emit KeyGenerated(groupId, generatedPublicKey);
        }

        // TODO: Removed _keyConfirmations data after all confirmed
    }

    /**
     * @notice Participant has to call this function to join an MPC request. Each request
     * requires exactly t + 1 members to join.
     */
    function joinRequest(uint256 requestId, uint256 myIndex) external {
        // TODO: Add auth

        Request storage status = _requests[requestId];
        if (status.publicKey.length == 0) revert RequestNotFound();

        KeyInfo memory info = _generatedKeys[status.publicKey];
        if (!info.confirmed) revert KeyNotFound();

        uint256 threshold = _groupThreshold[info.groupId];
        uint256 indices = status.participantIndices;
        uint256 confirmedCount = status.confirmedCount;
        if (confirmedCount > threshold) revert QuorumAlreadyReached();

        _ensureSenderIsClaimedParticipant(info.groupId, myIndex);

        uint256 myConfirm = 1 << (myIndex - 1);
        if (indices & myConfirm > 0) revert AttemptToRejoin();

        status.participantIndices = indices + myConfirm;
        status.confirmedCount = confirmedCount + 1;

        if (status.confirmedCount == threshold + 1) {
            StakeRequestDetails memory details = _stakeRequestDetails[requestId];
            if (details.amount > 0) {
                emit StakeRequestStarted(
                    requestId,
                    status.publicKey,
                    status.participantIndices,
                    details.nodeID,
                    details.amount,
                    details.startTime,
                    details.endTime
                );
            }
        }
    }

    /**
     * @notice Moves tokens from p-chain to c-chain.
     */
    function reportUTXO(
        bytes32 groupId,
        uint256 myIndex,
        bytes calldata genPubKey,
        bytes32 utxoTxID,
        uint32 utxoIndex
    ) external onlyGroupMember(groupId, myIndex) {
        if (utxoIndex > 1) revert Unrecognized();
        uint256 threshold = _groupThreshold[groupId];
        uint256 countBeforeMyself = _joinExportUTXOParticipantIndices[utxoTxID][utxoIndex].length;
        if (countBeforeMyself > threshold) return;

        _joinExportUTXOParticipantIndices[utxoTxID][utxoIndex].push(myIndex);

        if (countBeforeMyself == threshold) {
            uint256[] memory joinedIndices = _joinExportUTXOParticipantIndices[utxoTxID][utxoIndex];
            address destAddress = utxoIndex == 0 ? principalTreasuryAddress : rewardTreasuryAddress;
            emit ExportUTXORequest(utxoTxID, utxoIndex, destAddress, genPubKey, joinedIndices);
            delete _joinExportUTXOParticipantIndices[utxoTxID][utxoIndex];
        }
    }

    // -------------------------------------------------------------------------
    //  External view functions
    // -------------------------------------------------------------------------

    function getGroup(bytes32 groupId) external view returns (bytes[] memory, uint256) {
        uint256 count = _groupParticipantCount[groupId];
        if (count == 0) revert GroupNotFound();
        bytes[] memory participants = new bytes[](count);
        uint256 threshold = _groupThreshold[groupId];

        for (uint256 i = 0; i < count; i++) {
            participants[i] = _groupParticipants[groupId][i + 1].publicKey; // Participant index is 1-based.
        }
        return (participants, threshold);
    }

    function getKey(bytes calldata publicKey) external view returns (KeyInfo memory) {
        return _generatedKeys[publicKey];
    }

    // -------------------------------------------------------------------------
    //  Modifiers
    // -------------------------------------------------------------------------

    modifier onlyAvaLido() {
        if (msg.sender != avaLidoAddress) revert AvaLidoOnly();
        _;
    }

    modifier onlyGroupMember(bytes32 groupId, uint256 index) {
        _ensureSenderIsClaimedParticipant(groupId, index);
        _;
    }

    // -------------------------------------------------------------------------
    //  Internal functions
    // -------------------------------------------------------------------------

    // TODO: to deal with publickey param type modifier, currently use memory for testing convinience.
    function _handleStakeRequest(
        bytes memory publicKey,
        string calldata nodeID,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    ) internal {
        KeyInfo memory info = _generatedKeys[publicKey];
        if (!info.confirmed) revert KeyNotFound();

        // TODO: Validate input

        uint256 requestId = _getNextRequestId();
        Request storage status = _requests[requestId];
        status.publicKey = publicKey;
        status.requestType = RequestType.STAKE;

        StakeRequestDetails storage details = _stakeRequestDetails[requestId];

        details.nodeID = nodeID;
        details.amount = amount;
        details.startTime = startTime;
        details.endTime = endTime;
        emit StakeRequestAdded(requestId, publicKey, nodeID, amount, startTime, endTime);
    }

    function _getNextRequestId() internal returns (uint256) {
        _lastRequestId += 1;
        return _lastRequestId;
    }

    // -------------------------------------------------------------------------
    //  Private functions
    // -------------------------------------------------------------------------

    function _generatedKeyConfirmedByAll(bytes32 groupId, bytes calldata generatedPublicKey)
        private
        view
        returns (bool)
    {
        uint256 count = _groupParticipantCount[groupId];

        for (uint256 i = 0; i < count; i++) {
            if (!_keyConfirmations[generatedPublicKey][i + 1]) return false; // Participant index is 1-based.
        }
        return true;
    }

    /**
     * @dev converts a public key to ethereum address.
     * Reference: https://ethereum.stackexchange.com/questions/40897/get-address-from-public-key-in-solidity
     */
    function _calculateAddress(bytes memory pub) private pure returns (address addr) {
        bytes32 hash = keccak256(pub);
        assembly {
            mstore(0, hash)
            addr := mload(0)
        }
    }

    function _ensureSenderIsClaimedParticipant(bytes32 groupId, uint256 index) private view {
        if (msg.sender != _groupParticipants[groupId][index].ethAddress) revert InvalidGroupMembership();
    }
}
