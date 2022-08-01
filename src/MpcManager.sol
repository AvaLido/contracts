// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import "./Roles.sol";
import "./interfaces/IMpcManager.sol";

contract MpcManager is AccessControlEnumerable, IMpcManager, Initializable {
    uint256 constant GROUP_SIZE_SHIFT = 16;
    uint256 constant THRESHOLD_SHIFT = 8;
    bytes32 constant GROUP_ID_MASK = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000; // First 232 bits = Hash(PublicKeys), Next 8 bits = groupSize, Next 8 bits = threshold, Next 8 bits = reserved for party index
    bytes32 constant INIT_31_BYTE_MASK = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00;
    bytes32 constant LAST_BYTE_MASK = 0x00000000000000000000000000000000000000000000000000000000000000ff;
    uint256 constant INIT_BIT = 0x8000000000000000000000000000000000000000000000000000000000000000;
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
    error AttemptToReconfirmKey();

    error InvalidAmount();
    error QuorumAlreadyReached();
    error AttemptToRejoin();

    // Events
    event ParticipantAdded(bytes indexed publicKey, bytes32 groupId, uint256 index);
    event KeyGenerated(bytes32 indexed groupId, bytes publicKey);
    event KeygenRequestAdded(bytes32 indexed groupId);
    event StakeRequestAdded(
        uint256 requestNumber,
        bytes indexed publicKey,
        string nodeID,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    );

    event RequestStarted(bytes32 indexed requestHash, uint256 participantIndices);

    // Types
    struct ParticipantInfo {
        bytes publicKey;
        address ethAddress;
    }

    // State variables
    bytes public lastGenPubKey;
    address public lastGenAddress;

    address public avaLidoAddress;
    address public principalTreasuryAddress;
    address public rewardTreasuryAddress;

    // participantId -> participant
    mapping(bytes32 => ParticipantInfo) private _groupParticipants;

    // key -> groupId
    mapping(bytes => bytes32) private _keyToGroupIds;

    // key -> confirmation map
    mapping(bytes => uint256) private _keyConfirmations;

    // groupId -> requestHash -> request status
    mapping(bytes32 => mapping(bytes32 => uint256)) private _requestParticipations; // Last Byte = total-Confirmation, Rest = Participation flags (for max of 248 members)

    uint256 private _lastStakeRequestNumber;

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

        uint256 requestNumber = _getNextStakeRequestNumber();

        emit StakeRequestAdded(requestNumber, lastGenPubKey, nodeID, amount, startTime, endTime);
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
        uint256 groupSize = publicKeys.length;
        if (groupSize < 2 || groupSize > MAX_GROUP_SIZE) revert InvalidGroupSize();
        if (threshold < 1 || threshold >= groupSize) revert InvalidThreshold();

        bytes memory b;
        for (uint256 i = 0; i < groupSize; i++) {
            if (publicKeys[i].length != PUBKEY_LENGTH) revert InvalidPublicKey();
            b = bytes.concat(b, publicKeys[i]);
        }
        bytes32 groupId = keccak256(b);
        groupId =
            (groupId & GROUP_ID_MASK) |
            (bytes32(groupSize) << GROUP_SIZE_SHIFT) |
            (bytes32(uint256(threshold)) << THRESHOLD_SHIFT);

        bytes32 participantId = groupId | bytes32(uint256(1));
        address knownFirstParticipantAddr = _groupParticipants[participantId].ethAddress;
        if (knownFirstParticipantAddr != address(0)) revert AttemptToReaddGroup();

        for (uint256 i = 0; i < publicKeys.length; i++) {
            participantId = groupId | bytes32(i + 1);
            _groupParticipants[participantId].publicKey = publicKeys[i]; // Participant index is 1-based.
            _groupParticipants[participantId].ethAddress = _calculateAddress(publicKeys[i]); // Participant index is 1-based.
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
     * @param participantId The id of a party in an mpc group.
     * @param generatedPublicKey The generated public key.
     */
    function reportGeneratedKey(bytes32 participantId, bytes calldata generatedPublicKey)
        external
        onlyGroupMember(participantId)
    {
        uint8 myIndex = uint8(uint256(participantId & LAST_BYTE_MASK));
        uint8 groupSize = uint8(uint256((participantId >> GROUP_SIZE_SHIFT) & LAST_BYTE_MASK));
        uint256 confirmation = _keyConfirmations[generatedPublicKey];
        uint256 myConfirm = INIT_BIT >> (myIndex - 1);
        if ((confirmation & myConfirm) > 0) revert AttemptToReconfirmKey();

        uint256 indices = confirmation & uint256(INIT_31_BYTE_MASK);
        uint8 confirmedCount = uint8(confirmation & uint256(LAST_BYTE_MASK));
        indices += myConfirm;
        confirmedCount++;

        if (confirmedCount == groupSize) {
            bytes32 groupId = participantId & INIT_31_BYTE_MASK;
            _keyToGroupIds[generatedPublicKey] = groupId;
            lastGenPubKey = generatedPublicKey;
            lastGenAddress = _calculateAddress(generatedPublicKey);
            emit KeyGenerated(groupId, generatedPublicKey);
        }
        _keyConfirmations[generatedPublicKey] = indices | confirmedCount;
    }

    /**
     * @notice Participant has to call this function to join an MPC request. Each request
     * requires exactly t + 1 members to join.
     */
    function joinRequest(bytes32 participantId, bytes32 requestHash) external onlyGroupMember(participantId) {
        bytes32 groupId = participantId & INIT_31_BYTE_MASK;
        uint8 myIndex = uint8(uint256(participantId & LAST_BYTE_MASK));
        uint8 threshold = uint8(uint256((participantId >> THRESHOLD_SHIFT) & LAST_BYTE_MASK));

        uint256 participation = _requestParticipations[groupId][requestHash];
        uint8 confirmedCount = uint8(participation & uint256(LAST_BYTE_MASK));
        if (confirmedCount > threshold) revert QuorumAlreadyReached();

        uint256 indices = participation & uint256(INIT_31_BYTE_MASK);
        uint256 myConfirm = INIT_BIT >> (myIndex - 1);
        if (indices & myConfirm > 0) revert AttemptToRejoin();

        indices += myConfirm;
        confirmedCount++;

        if (confirmedCount == threshold + 1) {
            emit RequestStarted(requestHash, indices);
        }
        _requestParticipations[groupId][requestHash] = indices | confirmedCount;
    }

    // -------------------------------------------------------------------------
    //  External view functions
    // -------------------------------------------------------------------------

    function getGroup(bytes32 groupId) external view returns (bytes[] memory) {
        uint256 count = uint256((groupId >> GROUP_SIZE_SHIFT) & LAST_BYTE_MASK);
        if (count == 0) revert GroupNotFound();
        bytes[] memory participants = new bytes[](count);

        bytes32 participantId = groupId | bytes32(uint256(1));
        bytes memory participant1 = _groupParticipants[participantId].publicKey; // Participant index is 1-based.
        if (participant1.length == 0) revert GroupNotFound();
        participants[0] = participant1;

        for (uint256 i = 1; i < count; i++) {
            participantId = groupId | bytes32(i + 1);
            participants[i] = _groupParticipants[participantId].publicKey; // Participant index is 1-based.
        }
        return (participants);
    }

    function getGroupIdByKey(bytes calldata publicKey) external view returns (bytes32) {
        return _keyToGroupIds[publicKey];
    }

    // -------------------------------------------------------------------------
    //  Modifiers
    // -------------------------------------------------------------------------

    modifier onlyAvaLido() {
        if (msg.sender != avaLidoAddress) revert AvaLidoOnly();
        _;
    }

    modifier onlyGroupMember(bytes32 participantId) {
        if (msg.sender != _groupParticipants[participantId].ethAddress) revert InvalidGroupMembership();
        _;
    }

    // -------------------------------------------------------------------------
    //  Internal functions
    // -------------------------------------------------------------------------

    function _getNextStakeRequestNumber() internal returns (uint256) {
        _lastStakeRequestNumber += 1;
        return _lastStakeRequestNumber;
    }

    // -------------------------------------------------------------------------
    //  Private functions
    // -------------------------------------------------------------------------

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
