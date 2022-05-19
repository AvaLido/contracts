// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;
import "./interfaces/IMpcManager.sol";
import "./interfaces/IMpcCoordinator.sol";

contract MpcManager is IMpcManager, IMpcCoordinator {
    // TODO:
    // Key these statements for observation and testing purposes only
    // Considering remove them later before everything fixed up and get into production mode.
    bytes public _generatedKeyOnlyForTempTest;
    address public _calculateAddressForTempTest;
    uint256 public stakeNumber;
    uint256 public stakeAmount;

    enum RequestStatus {
        UNKNOWN,
        STARTED,
        COMPLETED
    }
    struct Request {
        bytes publicKey;
        bytes message;
        uint256[] participantIndices;
        RequestStatus status;
    }
    struct StakeRequestDetails {
        string nodeID;
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
    }
    // groupId -> number of participants in the group
    mapping(bytes32 => uint256) private _groupParticipantCount;
    // groupId -> threshold
    mapping(bytes32 => uint256) private _groupThreshold;
    // groupId -> index -> participant
    mapping(bytes32 => mapping(uint256 => bytes)) private _groupParticipants;

    // key -> groupId
    mapping(bytes => KeyInfo) private _generatedKeys;

    // key -> index -> confirmed
    mapping(bytes => mapping(uint256 => bool)) private _keyConfirmations;

    // request status
    mapping(uint256 => Request) private _requests;
    mapping(uint256 => StakeRequestDetails) private _stakeRequestDetails;
    uint256 private _lastRequestId;

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
        uint256[] participantIndices,
        string nodeID,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    );
    event SignRequestAdded(uint256 requestId, bytes indexed publicKey, bytes message);
    event SignRequestStarted(uint256 requestId, bytes indexed publicKey, bytes message);

    constructor() payable {}

    receive() external payable {}

    // TODO:
    // A convinient function for test, remove it for production.
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getStakeNumber() public view returns (uint256) {
        return stakeNumber;
    }

    function getStakeAmount() public view returns (uint256) {
        return stakeAmount;
    }

    function getStakeAddress() public view returns (address) {
        return _calculateAddressForTempTest;
    }

    // TODO: improve its logic, especially add publick selection logic.
    // Make sure call this function after key reported, and make sure fund the account adequately.
    function requestStake(
        string calldata nodeID,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    ) external payable {
        bytes memory publicKey = _generatedKeyOnlyForTempTest;
        address publicKeyAddress = _calculateAddressForTempTest;

        payable(publicKeyAddress).transfer(amount);
        handleStakeRequest(publicKey, nodeID, amount, startTime, endTime);

        stakeNumber += 1;
        stakeAmount += amount;
    }

    function createGroup(bytes[] calldata publicKeys, uint256 threshold) external {
        // TODO: Add auth
        // TODO: Check public keys are valid
        require(publicKeys.length > 1, "A group requires 2 or more participants.");
        require(threshold >= 1 && threshold < publicKeys.length, "Invalid threshold");

        bytes memory b = bytes.concat(bytes32(threshold));
        for (uint256 i = 0; i < publicKeys.length; i++) {
            b = bytes.concat(b, publicKeys[i]);
        }
        bytes32 groupId = keccak256(b);

        uint256 count = _groupParticipantCount[groupId];
        require(count == 0, "Group already exists.");
        _groupParticipantCount[groupId] = publicKeys.length;
        _groupThreshold[groupId] = threshold;

        for (uint256 i = 0; i < publicKeys.length; i++) {
            _groupParticipants[groupId][i + 1] = publicKeys[i]; // Participant index is 1-based.
            emit ParticipantAdded(publicKeys[i], groupId, i + 1);
        }
    }

    function requestKeygen(bytes32 groupId) external {
        // TODO: Add auth
        emit KeygenRequestAdded(groupId);
    }

    function reportGeneratedKey(
        bytes32 groupId,
        uint256 myIndex,
        bytes calldata generatedPublicKey
    ) external onlyGroupMember(groupId, myIndex) {
        // TODO: Add auth
        KeyInfo storage info = _generatedKeys[generatedPublicKey];

        require(!info.confirmed, "Key has already been confirmed by all participants.");

        // TODO: Check public key valid
        _keyConfirmations[generatedPublicKey][myIndex] = true;

        if (_generatedKeyConfirmedByAll(groupId, generatedPublicKey)) {
            info.groupId = groupId;
            info.confirmed = true;
            // TODO: The two sentence below for naive testing purpose, to deal with them furher.
            _generatedKeyOnlyForTempTest = generatedPublicKey;
            _calculateAddressForTempTest = _calculateAddress(generatedPublicKey);
            emit KeyGenerated(groupId, generatedPublicKey);
        }

        // TODO: Removed _keyConfirmations data after all confirmed
    }

    // TODO: to deal with publickey param type modifier, currently use memory for testing convinience.
    function handleStakeRequest(
        bytes memory publicKey,
        string calldata nodeID,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    ) public {
        // TODO: Add auth
        KeyInfo memory info = _generatedKeys[publicKey];
        require(info.confirmed, "Key doesn't exist or has not been confirmed.");

        // TODO: Validate input

        uint256 requestId = _getNextRequestId();
        Request storage status = _requests[requestId];
        status.publicKey = publicKey;
        // status.message is intentionally not set to indicate it's a StakeRequest

        StakeRequestDetails storage details = _stakeRequestDetails[requestId];

        details.nodeID = nodeID;
        details.amount = amount;
        details.startTime = startTime;
        details.endTime = endTime;
        emit StakeRequestAdded(requestId, publicKey, nodeID, amount, startTime, endTime);
    }

    function requestSign(bytes calldata publicKey, bytes calldata message) external {
        // TODO: Add auth
        KeyInfo memory info = _generatedKeys[publicKey];
        require(info.confirmed, "Key doesn't exist or has not been confirmed.");
        uint256 requestId = _getNextRequestId();
        Request storage status = _requests[requestId];
        status.publicKey = publicKey;
        status.message = message;
        emit SignRequestAdded(requestId, publicKey, message);
    }

    function joinRequest(uint256 requestId, uint256 myIndex) external {
        // TODO: Add auth

        Request storage status = _requests[requestId];
        require(status.publicKey.length > 0, "Request doesn't exist.");

        KeyInfo memory info = _generatedKeys[status.publicKey];
        require(info.confirmed, "Public key doesn't exist or has not been confirmed.");

        uint256 threshold = _groupThreshold[info.groupId];
        require(status.participantIndices.length <= threshold, "Cannot join anymore.");

        _ensureSenderIsClaimedParticipant(info.groupId, myIndex);

        for (uint256 i = 0; i < status.participantIndices.length; i++) {
            require(status.participantIndices[i] != myIndex, "Already joined.");
        }
        status.participantIndices.push(myIndex);

        if (status.participantIndices.length == threshold + 1) {
            if (status.message.length > 0) {
                emit SignRequestStarted(requestId, status.publicKey, status.message);
            } else {
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
    }

    function getGroup(bytes32 groupId) external view returns (bytes[] memory participants, uint256 threshold) {
        uint256 count = _groupParticipantCount[groupId];
        require(count > 0, "Group doesn't exist.");
        bytes[] memory participants = new bytes[](count);
        threshold = _groupThreshold[groupId];

        for (uint256 i = 0; i < count; i++) {
            participants[i] = _groupParticipants[groupId][i + 1];
        }
        return (participants, threshold);
    }

    function getKey(bytes calldata publicKey) external view returns (KeyInfo memory keyInfo) {
        keyInfo = _generatedKeys[publicKey];
    }

    modifier onlyGroupMember(bytes32 groupId, uint256 index) {
        _ensureSenderIsClaimedParticipant(groupId, index);
        _;
    }

    function _generatedKeyConfirmedByAll(bytes32 groupId, bytes calldata generatedPublicKey)
        private
        view
        returns (bool)
    {
        uint256 count = _groupParticipantCount[groupId];

        for (uint256 i = 0; i < count; i++) {
            if (!_keyConfirmations[generatedPublicKey][i + 1]) return false;
        }
        return true;
    }

    function _calculateAddress(bytes memory pub) private pure returns (address addr) {
        bytes32 hash = keccak256(pub);
        assembly {
            mstore(0, hash)
            addr := mload(0)
        }
    }

    function _ensureSenderIsClaimedParticipant(bytes32 groupId, uint256 index) private view {
        bytes memory publicKey = _groupParticipants[groupId][index];
        require(publicKey.length > 0, "Invalid groupId or index.");

        address member = _calculateAddress(publicKey);

        require(msg.sender == member, "Caller is not a group member");
    }

    function _getNextRequestId() internal returns (uint256) {
        _lastRequestId += 1;
        return _lastRequestId;
    }
}
