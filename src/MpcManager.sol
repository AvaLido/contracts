// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/security/Pausable.sol";
import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import "./Roles.sol";
import "./interfaces/IMpcManager.sol";

contract MpcManager is Pausable, AccessControlEnumerable, IMpcManager, Initializable {
    bytes32 constant GROUP_ID_MASK = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000; // Second last byte for groupSize, last byte for threshold
    bytes32 constant LAST_BYTE_MASK = 0x00000000000000000000000000000000000000000000000000000000000000ff;
    uint256 constant INIT_BIT = 0x8000000000000000000000000000000000000000000000000000000000000000;
    uint256 constant HEAD_MASK = 0xff00000000000000000000000000000000000000000000000000000000000000;
    uint256 constant TAIL_MASK = 0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant MAX_GROUP_SIZE = 248;
    uint256 constant PUBKEY_LENGTH = 64;
    // Errors
    error AvaLidoOnly();

    error InvalidGroupSize(); // A group requires 2 or more participants.
    error InvalidThreshold(); // Threshold has to be in range [1, n - 1].
    error InvalidPublicKey();
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

    event RequestStarted(bytes32 indexed requestId, uint256 participantIndices);

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
        uint256 participantIndices
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
        uint256 requestType;
        uint256 participantIndices;
        uint8 confirmedCount;
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

    // groupId -> index -> participant
    mapping(bytes32 => mapping(uint256 => ParticipantInfo)) private _groupParticipants;

    // key -> groupId
    mapping(bytes => KeyInfo) private _generatedKeys;

    // key -> index -> confirmed
    mapping(bytes => mapping(uint256 => bool)) private _keyConfirmations;

    // groupId -> requestId -> request status
    mapping(bytes32 => mapping(bytes32 => uint256)) private _requestParticipations; // Last Byte = total-Confirmation, Rest = Participation flags (for max of 248 members)
    mapping(uint256 => StakeRequestDetails) private _stakeRequestDetails;
    uint256 private _lastRequestId;

    // utxoTxId -> utxoIndex -> joinExportUTXOParticipantIndices
    mapping(bytes32 => mapping(uint32 => Request)) private _p2cRequests;

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

        KeyInfo memory info = _generatedKeys[lastGenPubKey];
        if (!info.confirmed) revert KeyNotFound();

        uint256 requestId = _getNextRequestId();

        emit StakeRequestAdded(requestId, lastGenPubKey, nodeID, amount, startTime, endTime);
    }

    /**
     * @notice Admin will call this function to create an MPC group consisting of n members
     * and a specified threshold t. The signing can be performed by any t + 1 participants
     * from the group.
     * @param publicKeys The public keys which identify the n group members.
     * @param threshold The threshold t. Note: t + 1 participants are required to complete a
     * signing.
     */
    function createGroup(bytes[] calldata publicKeys, uint8 threshold) external onlyRole(ROLE_MPC_MANAGER) {
        if (publicKeys.length < 2 || publicKeys.length > MAX_GROUP_SIZE) revert InvalidGroupSize();
        if (threshold < 1 || threshold >= publicKeys.length) revert InvalidThreshold();

        bytes memory b;
        for (uint256 i = 0; i < publicKeys.length; i++) {
            if (publicKeys[i].length != PUBKEY_LENGTH) revert InvalidPublicKey();
            b = bytes.concat(b, publicKeys[i]);
        }
        bytes32 groupId = keccak256(b);
        groupId = (groupId & GROUP_ID_MASK) | (bytes32(publicKeys.length) << 8) | bytes32(uint256(threshold));

        address knownFirstParticipantAddr = _groupParticipants[groupId][1].ethAddress;
        if (knownFirstParticipantAddr != address(0)) revert AttemptToReaddGroup();

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
        uint8 myIndex,
        bytes calldata generatedPublicKey
    ) external onlyGroupMember(groupId, myIndex) {
        KeyInfo storage info = _generatedKeys[generatedPublicKey];

        if (info.confirmed) revert AttemptToReconfirmKey();

        _keyConfirmations[generatedPublicKey][myIndex] = true;

        if (_generatedKeyConfirmedByAll(groupId, generatedPublicKey)) {
            info.groupId = groupId;
            info.confirmed = true;
            lastGenPubKey = generatedPublicKey;
            lastGenAddress = _calculateAddress(generatedPublicKey);
            emit KeyGenerated(groupId, generatedPublicKey);
        }
    }

    /**
     * @notice Participant has to call this function to join an MPC request. Each request
     * requires exactly t + 1 members to join.
     */
    function joinRequest(
        bytes32 groupId,
        uint8 myIndex,
        bytes32 requestId
    ) external onlyGroupMember(groupId, myIndex) {
        uint256 participation = _requestParticipations[groupId][requestId];

        uint8 threshold = uint8(uint256(groupId & LAST_BYTE_MASK));

        uint8 confirmedCount = uint8(participation & TAIL_MASK);
        if (confirmedCount > threshold) revert QuorumAlreadyReached();

        uint256 indices = participation & HEAD_MASK;

        uint256 myConfirm = INIT_BIT >> (myIndex - 1);
        if (indices & myConfirm > 0) revert AttemptToRejoin();

        indices += myConfirm;
        confirmedCount++;

        if (confirmedCount == threshold + 1) {
            emit RequestStarted(requestId, indices);
        }
        _requestParticipations[groupId][requestId] = indices | confirmedCount;
    }

    /**
     * @notice Moves tokens from p-chain to c-chain.
     */
    function reportUTXO(
        bytes32 groupId,
        uint8 myIndex,
        bytes calldata publicKey,
        bytes32 utxoTxID,
        uint32 utxoIndex
    ) external onlyGroupMember(groupId, myIndex) {
        if (utxoIndex > 1) revert Unrecognized();
        uint8 threshold = uint8(uint256(groupId & LAST_BYTE_MASK));

        Request storage status = _p2cRequests[utxoTxID][utxoIndex];
        if (status.publicKey.length == 0) {
            status.publicKey = publicKey;
            status.requestType = 2;
        }

        if (status.confirmedCount > threshold) return;

        uint256 myConfirm = 1 << (myIndex - 1);
        if (status.participantIndices & myConfirm > 0) revert AttemptToRejoin();

        status.participantIndices = status.participantIndices + myConfirm;
        status.confirmedCount = status.confirmedCount + 1;

        if (status.confirmedCount == threshold + 1) {
            address destAddress = utxoIndex == 0 ? principalTreasuryAddress : rewardTreasuryAddress;
            emit ExportUTXORequest(utxoTxID, utxoIndex, destAddress, publicKey, status.participantIndices);
        }
    }

    // -------------------------------------------------------------------------
    //  External view functions
    // -------------------------------------------------------------------------

    function getGroup(bytes32 groupId) external view returns (bytes[] memory, uint256) {
        uint8 count = uint8(uint256((groupId >> 8) & LAST_BYTE_MASK));
        if (count == 0) revert GroupNotFound();
        bytes[] memory participants = new bytes[](count);
        uint8 threshold = uint8(uint256(groupId & LAST_BYTE_MASK));

        for (uint8 i = 0; i < count; i++) {
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
        if (msg.sender != _groupParticipants[groupId][index].ethAddress) revert InvalidGroupMembership();
        _;
    }

    // -------------------------------------------------------------------------
    //  Internal functions
    // -------------------------------------------------------------------------

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
        uint8 count = uint8(uint256((groupId >> 8) & LAST_BYTE_MASK));

        for (uint8 i = 0; i < count; i++) {
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
}
