// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

contract MockMpcManager {
    enum KeygenStatus {
        NOT_EXIST,
        REQUESTED,
        COMPLETED,
        CANCELED
    }
    uint256 constant MAX_GROUP_SIZE = 248;
    uint256 constant PUBKEY_LENGTH = 64;
    // Errors
    error AvaLidoOnly();

    error InvalidGroupSize(); // A group requires 2 or more participants.
    error InvalidThreshold(); // Threshold has to be in range [1, n - 1].
    error InvalidPublicKey();
    error PublicKeysNotSorted();
    error GroupNotFound();
    error InvalidGroupMembership();
    error AttemptToReaddGroup();

    error KeygenNotRequested();
    error GotPendingKeygenRequest();
    error NotInAuthorizedGroup();
    error KeyNotGenerated();
    error AttemptToReconfirmKey();

    error InvalidAmount();
    error QuorumAlreadyReached();
    error AttemptToRejoin();

    error TransferFailed();

    // Events
    event ParticipantAdded(bytes indexed publicKey, bytes32 groupId, uint256 index);
    event KeyGenerated(bytes32 indexed groupId, bytes publicKey);
    event KeygenRequestAdded(bytes32 indexed groupId, uint256 requestNumber);
    event KeygenRequestCanceled(bytes32 indexed groupId, uint256 requestNumber);
    event StakeRequestAdded(
        uint256 requestNumber,
        bytes indexed publicKey,
        string nodeID,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    );

    event RequestStarted(bytes32 requestHash, uint256 participantIndices);

    // Types
    struct ParticipantInfo {
        bytes publicKey;
        address ethAddress;
    }

    constructor() {}

    function addParticipant(
        bytes calldata publicKey,
        bytes32 groupId,
        uint256 index
    ) external {
        emit ParticipantAdded(publicKey, groupId, index);
    }

    function addKey(bytes32 groupId, bytes calldata publicKey) external {
        emit KeyGenerated(groupId, publicKey);
    }

    function addStakeRequest(
        uint256 requestNumber,
        bytes calldata publicKey,
        string calldata nodeID,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    ) external {
        // uint256 startTime = block.timestamp + 1 hours;
        // uint256 endTime = startTime + 30;
        emit StakeRequestAdded(requestNumber, publicKey, nodeID, amount, startTime, endTime);
    }

    function startRequest(bytes32 requestHash, uint256 participantIndices) external {
        emit RequestStarted(requestHash, participantIndices);
    }
}
