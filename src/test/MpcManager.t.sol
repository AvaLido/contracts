// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./cheats.sol";
import "./helpers.sol";

import "../interfaces/IMpcManager.sol";
import "../MpcManager.sol";

contract MpcManagerTest is DSTest, Helpers {
    uint8 constant MPC_THRESHOLD = 1;
    bytes32 constant MPC_BIG_GROUP_ID = hex"f86c407f80a75fa8151d0b55d4575789a7d8c663672286aad7ddfdf8f90c0900";
    bytes32 constant MPC_BIG_P01_ID = hex"f86c407f80a75fa8151d0b55d4575789a7d8c663672286aad7ddfdf8f90c0901";
    bytes32 constant MPC_BIG_P02_ID = hex"f86c407f80a75fa8151d0b55d4575789a7d8c663672286aad7ddfdf8f90c0902";
    bytes32 constant MPC_BIG_P03_ID = hex"f86c407f80a75fa8151d0b55d4575789a7d8c663672286aad7ddfdf8f90c0903";
    bytes32 constant MPC_BIG_P04_ID = hex"f86c407f80a75fa8151d0b55d4575789a7d8c663672286aad7ddfdf8f90c0904";
    bytes32 constant MPC_BIG_P05_ID = hex"f86c407f80a75fa8151d0b55d4575789a7d8c663672286aad7ddfdf8f90c0905";
    bytes32 constant MPC_BIG_P06_ID = hex"f86c407f80a75fa8151d0b55d4575789a7d8c663672286aad7ddfdf8f90c0906";
    bytes32 constant MPC_BIG_P07_ID = hex"f86c407f80a75fa8151d0b55d4575789a7d8c663672286aad7ddfdf8f90c0907";
    bytes32 constant MPC_BIG_P08_ID = hex"f86c407f80a75fa8151d0b55d4575789a7d8c663672286aad7ddfdf8f90c0908";
    bytes32 constant MPC_BIG_P09_ID = hex"f86c407f80a75fa8151d0b55d4575789a7d8c663672286aad7ddfdf8f90c0909";
    bytes32 constant MPC_BIG_P10_ID = hex"f86c407f80a75fa8151d0b55d4575789a7d8c663672286aad7ddfdf8f90c090a";
    bytes32 constant MPC_BIG_P11_ID = hex"f86c407f80a75fa8151d0b55d4575789a7d8c663672286aad7ddfdf8f90c090b";
    bytes32 constant MPC_BIG_P12_ID = hex"f86c407f80a75fa8151d0b55d4575789a7d8c663672286aad7ddfdf8f90c090c";
    bytes constant TOO_SHORT_PUKEY =
        hex"ee5cd601a19cd9bb95fe7be8b1566b73c51d3e7e375359c129b1d77bb4b3e6f06766bde6ff723360cee7f89abab428717f811f460ebf67f5186f75a9f4288d";

    bytes constant MESSAGE_TO_SIGN = bytes("foo");
    uint256 constant STAKE_AMOUNT = 30 ether;
    uint256 constant STAKE_START_TIME = 1640966400; // 2022-01-01
    uint256 constant STAKE_END_TIME = 1642176000; // 2022-01-15

    bytes32 constant UTXO_TX_ID = hex"5245afb3ad9c5c3c9430a7034464f42cee023f228d46ebcae7544759d2779caa";

    address AVALIDO_ADDRESS = 0x1000000000000000000000000000000000000001;

    address PRINCIPAL_TREASURY_ADDR = 0xd94fC5fd8812ddE061F420D4146bc88e03b6787c;
    address REWARD_TREASURY_ADDR = 0xe8025f13E6bF0Db21212b0Dd6AEBc4F3d1FB03ce;

    MpcManager mpcManager;
    bytes[] pubKeys = new bytes[](3);

    enum KeygenStatus {
        NOT_EXIST,
        REQUESTED,
        COMPLETED,
        CANCELED
    }
    event ParticipantAdded(bytes indexed publicKey, bytes32 groupId, uint256 index);
    event KeygenRequestAdded(bytes32 indexed groupId, uint256 requestNumber);
    event KeygenRequestCanceled(bytes32 indexed groupId, uint256 requestNumber);
    event KeyGenerated(bytes32 indexed groupId, bytes publicKey);
    event SignRequestAdded(uint256 requestId, bytes indexed publicKey, bytes message);
    event SignRequestStarted(uint256 requestId, bytes indexed publicKey, bytes message);
    event RequestStarted(bytes32 indexed requestId, uint256 participantIndices);
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
        uint256 participantIndices
    );

    function resetParticipantPublicKeys() public {
        pubKeys[0] = MPC_PLAYER_1_PUBKEY;
        pubKeys[1] = MPC_PLAYER_2_PUBKEY;
        pubKeys[2] = MPC_PLAYER_3_PUBKEY;
    }

    function setUp() public {
        MpcManager _mpcManager = new MpcManager();
        mpcManager = MpcManager(proxyWrapped(address(_mpcManager), ROLE_PROXY_ADMIN));
        mpcManager.initialize(
            MPC_ADMIN_ADDRESS,
            PAUSE_ADMIN_ADDRESS,
            AVALIDO_ADDRESS,
            PRINCIPAL_TREASURY_ADDR,
            REWARD_TREASURY_ADDR
        );
        pubKeys[0] = MPC_PLAYER_1_PUBKEY;
        pubKeys[1] = MPC_PLAYER_2_PUBKEY;
        pubKeys[2] = MPC_PLAYER_3_PUBKEY;
    }

    // -------------------------------------------------------------------------
    //  Test cases
    // -------------------------------------------------------------------------
    function testCreateGroupTooBig() public {
        // Exceeding max allowed groupSize (=248)
        bytes[] memory pubKeysTooBig = new bytes[](249);
        for (uint256 i = 0; i < 249; i++) {
            pubKeysTooBig[i] = MPC_PLAYER_1_PUBKEY;
        }
        cheats.prank(MPC_ADMIN_ADDRESS);
        cheats.expectRevert(MpcManager.InvalidGroupSize.selector);
        mpcManager.createGroup(pubKeysTooBig, 200);
    }

    function testGroupOfSize12() public {
        bytes[] memory pubKeys12 = new bytes[](12);
        pubKeys12[0] = MPC_BIG_P01_PUBKEY;
        pubKeys12[1] = MPC_BIG_P02_PUBKEY;
        pubKeys12[2] = MPC_BIG_P03_PUBKEY;
        pubKeys12[3] = MPC_BIG_P04_PUBKEY;
        pubKeys12[4] = MPC_BIG_P05_PUBKEY;
        pubKeys12[5] = MPC_BIG_P06_PUBKEY;
        pubKeys12[6] = MPC_BIG_P07_PUBKEY;
        pubKeys12[7] = MPC_BIG_P08_PUBKEY;
        pubKeys12[8] = MPC_BIG_P09_PUBKEY;
        pubKeys12[9] = MPC_BIG_P10_PUBKEY;
        pubKeys12[10] = MPC_BIG_P11_PUBKEY;
        pubKeys12[11] = MPC_BIG_P12_PUBKEY;
        cheats.prank(MPC_ADMIN_ADDRESS);
        mpcManager.createGroup(pubKeys12, 9);
        cheats.prank(MPC_ADMIN_ADDRESS);
        mpcManager.requestKeygen(MPC_BIG_GROUP_ID);

        bytes[] memory participants = mpcManager.getGroup(MPC_BIG_GROUP_ID);
        assertEq0(pubKeys12[0], participants[0]);
        assertEq0(pubKeys12[1], participants[1]);
        assertEq0(pubKeys12[2], participants[2]);

        cheats.prank(MPC_BIG_P01_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P01_ID, MPC_GENERATED_PUBKEY);
        cheats.prank(MPC_BIG_P02_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P02_ID, MPC_GENERATED_PUBKEY);
        cheats.prank(MPC_BIG_P03_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P03_ID, MPC_GENERATED_PUBKEY);
        cheats.prank(MPC_BIG_P04_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P04_ID, MPC_GENERATED_PUBKEY);
        cheats.prank(MPC_BIG_P05_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P05_ID, MPC_GENERATED_PUBKEY);
        cheats.prank(MPC_BIG_P06_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P06_ID, MPC_GENERATED_PUBKEY);
        cheats.prank(MPC_BIG_P07_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P07_ID, MPC_GENERATED_PUBKEY);
        cheats.prank(MPC_BIG_P08_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P08_ID, MPC_GENERATED_PUBKEY);
        cheats.prank(MPC_BIG_P09_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P09_ID, MPC_GENERATED_PUBKEY);
        cheats.prank(MPC_BIG_P10_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P10_ID, MPC_GENERATED_PUBKEY);
        cheats.prank(MPC_BIG_P11_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P11_ID, MPC_GENERATED_PUBKEY);

        cheats.expectEmit(false, false, true, true);
        emit KeyGenerated(MPC_BIG_GROUP_ID, MPC_GENERATED_PUBKEY);

        cheats.prank(MPC_BIG_P12_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_BIG_P12_ID, MPC_GENERATED_PUBKEY);
    }

    function testCreateGroup() public {
        // Non admin
        cheats.prank(USER1_ADDRESS);
        cheats.expectRevert(
            "AccessControl: account 0xd8da6bf26964af9d7eed9e03e53415d37aa96045 is missing role 0x9fece4792c7ff5d25a4f6041da7db799a6228be21fcb6358ef0b12f1dd685cb6"
        );
        mpcManager.createGroup(pubKeys, MPC_THRESHOLD);

        cheats.prank(MPC_ADMIN_ADDRESS);
        // Invalid public key
        pubKeys[2] = TOO_SHORT_PUKEY;
        cheats.expectRevert(MpcManager.InvalidPublicKey.selector);
        mpcManager.createGroup(pubKeys, MPC_THRESHOLD);

        // Success case
        resetParticipantPublicKeys();
        cheats.prank(MPC_ADMIN_ADDRESS);
        cheats.expectEmit(false, false, true, true);
        emit ParticipantAdded(MPC_PLAYER_1_PUBKEY, MPC_GROUP_ID, 1);
        emit ParticipantAdded(MPC_PLAYER_2_PUBKEY, MPC_GROUP_ID, 2);
        emit ParticipantAdded(MPC_PLAYER_3_PUBKEY, MPC_GROUP_ID, 3);
        mpcManager.createGroup(pubKeys, MPC_THRESHOLD);
    }

    function testGetGroup() public {
        setupGroup();
        bytes[] memory participants = mpcManager.getGroup(MPC_GROUP_ID);
        assertEq0(pubKeys[0], participants[0]);
        assertEq0(pubKeys[1], participants[1]);
        assertEq0(pubKeys[2], participants[2]);
    }

    function testKeygenRequest() public {
        setupGroup();

        cheats.prank(MPC_ADMIN_ADDRESS);
        cheats.expectEmit(false, false, true, true);
        emit KeygenRequestAdded(MPC_GROUP_ID, 1);
        mpcManager.requestKeygen(MPC_GROUP_ID);
        assertEq(uint256(mpcManager.lastKeygenRequest()), uint256(MPC_GROUP_ID) + uint8(KeygenStatus.REQUESTED));

        // Can cancel before started
        cheats.prank(MPC_ADMIN_ADDRESS);
        cheats.expectEmit(false, false, true, true);
        emit KeygenRequestCanceled(MPC_GROUP_ID, 1);
        mpcManager.cancelKeygen();
        assertEq(uint256(mpcManager.lastKeygenRequest()), uint256(MPC_GROUP_ID) + uint8(KeygenStatus.CANCELED));
        // Cannot report if canceled
        cheats.prank(MPC_PLAYER_1_ADDRESS);
        cheats.expectRevert(MpcManager.KeygenNotRequested.selector);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT1_ID, MPC_GENERATED_PUBKEY);

        // Request again
        cheats.prank(MPC_ADMIN_ADDRESS);
        mpcManager.requestKeygen(MPC_GROUP_ID);

        cheats.prank(MPC_PLAYER_1_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT1_ID, MPC_GENERATED_PUBKEY);
        cheats.prank(MPC_PLAYER_2_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT2_ID, MPC_GENERATED_PUBKEY);

        // Can cancel before done
        cheats.prank(MPC_ADMIN_ADDRESS);
        mpcManager.cancelKeygen();

        cheats.prank(MPC_ADMIN_ADDRESS);
        mpcManager.requestKeygen(MPC_GROUP_ID);

        cheats.prank(MPC_PLAYER_1_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT1_ID, MPC_GENERATED_PUBKEY);
        cheats.prank(MPC_PLAYER_2_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT2_ID, MPC_GENERATED_PUBKEY);
        cheats.prank(MPC_PLAYER_3_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT3_ID, MPC_GENERATED_PUBKEY);

        // Cannot cancel after done
        cheats.prank(MPC_ADMIN_ADDRESS);
        mpcManager.cancelKeygen();
    }

    function testReportGeneratedKey() public {
        setupKeygenRequest();

        // first participant reports generated key
        cheats.prank(MPC_PLAYER_1_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT1_ID, MPC_GENERATED_PUBKEY);

        // second participant reports generated key
        cheats.prank(MPC_PLAYER_2_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT2_ID, MPC_GENERATED_PUBKEY);

        // event is emitted when the last participant reports generated key
        cheats.expectEmit(false, false, true, true);
        emit KeyGenerated(MPC_GROUP_ID, MPC_GENERATED_PUBKEY);

        cheats.prank(MPC_PLAYER_3_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT3_ID, MPC_GENERATED_PUBKEY);
    }

    function testGetKey() public {
        setupKey();
        bytes32 groupId = mpcManager.getGroupIdByKey(MPC_GENERATED_PUBKEY);
        assertEq(MPC_GROUP_ID, groupId);
    }

    function testRequestStaking() public {
        // Called by wrong sender
        cheats.prank(USER1_ADDRESS);
        cheats.deal(USER1_ADDRESS, STAKE_AMOUNT);
        cheats.expectRevert(MpcManager.AvaLidoOnly.selector);
        mpcManager.requestStake{value: STAKE_AMOUNT}(VALIDATOR_1, STAKE_AMOUNT, STAKE_START_TIME, STAKE_END_TIME);

        // Called before keygen
        cheats.prank(AVALIDO_ADDRESS);
        cheats.deal(AVALIDO_ADDRESS, STAKE_AMOUNT);

        cheats.expectRevert(MpcManager.KeyNotGenerated.selector);
        mpcManager.requestStake{value: STAKE_AMOUNT}(VALIDATOR_1, STAKE_AMOUNT, STAKE_START_TIME, STAKE_END_TIME);

        setupKey();

        // Called with incorrect amount
        cheats.prank(AVALIDO_ADDRESS);
        cheats.deal(AVALIDO_ADDRESS, STAKE_AMOUNT);
        cheats.expectRevert(MpcManager.InvalidAmount.selector);
        mpcManager.requestStake{value: STAKE_AMOUNT - 1}(VALIDATOR_1, STAKE_AMOUNT, STAKE_START_TIME, STAKE_END_TIME);

        // Called with correct sender and after keygen
        cheats.prank(AVALIDO_ADDRESS);
        cheats.deal(AVALIDO_ADDRESS, STAKE_AMOUNT);
        cheats.expectEmit(false, false, true, true);
        emit StakeRequestAdded(1, MPC_GENERATED_PUBKEY, VALIDATOR_1, STAKE_AMOUNT, STAKE_START_TIME, STAKE_END_TIME);
        mpcManager.requestStake{value: STAKE_AMOUNT}(VALIDATOR_1, STAKE_AMOUNT, STAKE_START_TIME, STAKE_END_TIME);
        assertEq(address(MPC_GENERATED_ADDRESS).balance, STAKE_AMOUNT);
    }

    function testCannotRequestStakingWhenPaused() public {
        setupKey();
        cheats.prank(PAUSE_ADMIN_ADDRESS);
        mpcManager.pause();

        cheats.deal(AVALIDO_ADDRESS, STAKE_AMOUNT);
        cheats.prank(AVALIDO_ADDRESS);
        cheats.expectRevert("Pausable: paused");
        mpcManager.requestStake{value: STAKE_AMOUNT}(VALIDATOR_1, STAKE_AMOUNT, STAKE_START_TIME, STAKE_END_TIME);

        cheats.prank(PAUSE_ADMIN_ADDRESS);
        mpcManager.resume();
        cheats.prank(AVALIDO_ADDRESS);
        cheats.expectEmit(false, false, true, true);
        emit StakeRequestAdded(1, MPC_GENERATED_PUBKEY, VALIDATOR_1, STAKE_AMOUNT, STAKE_START_TIME, STAKE_END_TIME);
        mpcManager.requestStake{value: STAKE_AMOUNT}(VALIDATOR_1, STAKE_AMOUNT, STAKE_START_TIME, STAKE_END_TIME);
        assertEq(address(MPC_GENERATED_ADDRESS).balance, STAKE_AMOUNT);
    }

    function testJoinStakingRequest() public {
        setupStakingRequest();

        cheats.prank(MPC_PLAYER_1_ADDRESS);
        mpcManager.joinRequest(MPC_PARTICIPANT1_ID, bytes32(uint256(1)));

        // Event emitted after required t+1 participants have joined
        cheats.expectEmit(false, false, true, true);
        uint256 indices = INDEX_1 + INDEX_2;
        emit RequestStarted(bytes32(uint256(1)), indices);
        cheats.prank(MPC_PLAYER_2_ADDRESS);
        mpcManager.joinRequest(MPC_PARTICIPANT2_ID, bytes32(uint256(1)));

        // Cannot join anymore after required t+1 participants have joined
        cheats.prank(MPC_PLAYER_3_ADDRESS);
        cheats.expectRevert(MpcManager.QuorumAlreadyReached.selector);
        mpcManager.joinRequest(MPC_PARTICIPANT3_ID, bytes32(uint256(1)));
    }

    // -------------------------------------------------------------------------
    //  Private helper functions
    // -------------------------------------------------------------------------

    function setupGroup() private {
        cheats.prank(MPC_ADMIN_ADDRESS);
        mpcManager.createGroup(pubKeys, MPC_THRESHOLD);
    }

    function setupKeygenRequest() private {
        setupGroup();
        cheats.prank(MPC_ADMIN_ADDRESS);
        mpcManager.requestKeygen(MPC_GROUP_ID);
    }

    function setupKey() private {
        setupKeygenRequest();
        cheats.prank(MPC_PLAYER_1_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT1_ID, MPC_GENERATED_PUBKEY);
        cheats.prank(MPC_PLAYER_2_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT2_ID, MPC_GENERATED_PUBKEY);
        cheats.prank(MPC_PLAYER_3_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_PARTICIPANT3_ID, MPC_GENERATED_PUBKEY);
    }

    function setupStakingRequest() private {
        setupKey();
        cheats.prank(AVALIDO_ADDRESS);
        cheats.deal(AVALIDO_ADDRESS, STAKE_AMOUNT);
        mpcManager.requestStake{value: STAKE_AMOUNT}(VALIDATOR_1, STAKE_AMOUNT, STAKE_START_TIME, STAKE_END_TIME);
    }
}

contract ParticipantIdHelpersTest is DSTest, Helpers {
    function setUp() public {}

    function testMakeGroupId() public {
        bytes32 groupId = ParticipantIdHelpers.makeGroupId(MPC_GROUP_HASH, 3, 1);
        assertEq(groupId, MPC_GROUP_ID);
    }

    function testMakeParticipantId() public {
        bytes32 participantId = ParticipantIdHelpers.makeParticipantId(MPC_GROUP_ID, 1);
        assertEq(participantId, MPC_PARTICIPANT1_ID);
        participantId = ParticipantIdHelpers.makeParticipantId(MPC_GROUP_ID, 2);
        assertEq(participantId, MPC_PARTICIPANT2_ID);
        participantId = ParticipantIdHelpers.makeParticipantId(MPC_GROUP_ID, 3);
        assertEq(participantId, MPC_PARTICIPANT3_ID);
    }

    function testGetGroupSize() public {
        uint8 groupSize = ParticipantIdHelpers.getGroupSize(MPC_GROUP_ID);
        assertEq(groupSize, 3);
        groupSize = ParticipantIdHelpers.getGroupSize(MPC_PARTICIPANT1_ID);
        assertEq(groupSize, 3);
        groupSize = ParticipantIdHelpers.getGroupSize(MPC_PARTICIPANT2_ID);
        assertEq(groupSize, 3);
        groupSize = ParticipantIdHelpers.getGroupSize(MPC_PARTICIPANT3_ID);
        assertEq(groupSize, 3);
    }

    function testGetThreshold() public {
        uint8 threshold = ParticipantIdHelpers.getThreshold(MPC_GROUP_ID);
        assertEq(threshold, 1);
        threshold = ParticipantIdHelpers.getThreshold(MPC_PARTICIPANT1_ID);
        assertEq(threshold, 1);
        threshold = ParticipantIdHelpers.getThreshold(MPC_PARTICIPANT2_ID);
        assertEq(threshold, 1);
        threshold = ParticipantIdHelpers.getThreshold(MPC_PARTICIPANT3_ID);
        assertEq(threshold, 1);
    }

    function testGetGroupId() public {
        bytes32 groupId = ParticipantIdHelpers.getGroupId(MPC_PARTICIPANT1_ID);
        assertEq(groupId, MPC_GROUP_ID);
        groupId = ParticipantIdHelpers.getGroupId(MPC_PARTICIPANT2_ID);
        assertEq(groupId, MPC_GROUP_ID);
        groupId = ParticipantIdHelpers.getGroupId(MPC_PARTICIPANT3_ID);
        assertEq(groupId, MPC_GROUP_ID);
    }

    function testGetParticipantIndex() public {
        uint8 participantIndex = ParticipantIdHelpers.getParticipantIndex(MPC_PARTICIPANT1_ID);
        assertEq(participantIndex, 1);
        participantIndex = ParticipantIdHelpers.getParticipantIndex(MPC_PARTICIPANT2_ID);
        assertEq(participantIndex, 2);
        participantIndex = ParticipantIdHelpers.getParticipantIndex(MPC_PARTICIPANT3_ID);
        assertEq(participantIndex, 3);
    }
}

contract ConfirmationHelpersTest is DSTest, Helpers {
    bytes32 constant INDICES = hex"73553de49378e407b656cae022df20a11de995d35221910115cfc0993c483700";
    uint8 constant CONFIRMATION_COUNT = 115;
    bytes32 constant CONFIRMATION = hex"73553de49378e407b656cae022df20a11de995d35221910115cfc0993c483773";

    function testMakeConfirmation() public {
        uint256 confirmation = ConfirmationHelpers.makeConfirmation(uint256(INDICES), CONFIRMATION_COUNT);
        assertEq(confirmation, uint256(CONFIRMATION));
    }

    function testParseConfirmation() public {
        (uint256 indices, uint8 count) = ConfirmationHelpers.parseConfirmation(uint256(CONFIRMATION));
        assertEq(indices, uint256(INDICES));
        assertEq(count, CONFIRMATION_COUNT);
    }

    function testConfirm() public {
        uint256 confirm = ConfirmationHelpers.confirm(1);
        assertEq(confirm, uint256(INDEX_1));
        confirm = ConfirmationHelpers.confirm(2);
        assertEq(confirm, uint256(INDEX_2));
        confirm = ConfirmationHelpers.confirm(3);
        assertEq(confirm, uint256(INDEX_3));
    }
}

contract KeygenStatusHelpersTest is DSTest, Helpers {
    function testMakeKeygenRequest() public {
        bytes32 req = KeygenStatusHelpers.makeKeygenRequest(MPC_GROUP_ID, 1);
        assertEq(uint256(req), uint256(MPC_GROUP_ID) + 1);
        req = KeygenStatusHelpers.makeKeygenRequest(MPC_GROUP_ID, 2);
        assertEq(uint256(req), uint256(MPC_GROUP_ID) + 2);
        req = KeygenStatusHelpers.makeKeygenRequest(MPC_GROUP_ID, 3);
        assertEq(uint256(req), uint256(MPC_GROUP_ID) + 3);
        req = KeygenStatusHelpers.makeKeygenRequest(MPC_GROUP_ID, 4);
        assertEq(uint256(req), uint256(MPC_GROUP_ID) + 4);
    }

    function testGetGroupId() public {
        bytes32 req = bytes32(uint256(MPC_GROUP_ID) + 1);
        bytes32 groupId = KeygenStatusHelpers.getGroupId(req);
        assertEq(groupId, MPC_GROUP_ID);
        req = bytes32(uint256(MPC_GROUP_ID) + 2);
        groupId = KeygenStatusHelpers.getGroupId(req);
        assertEq(groupId, MPC_GROUP_ID);
        req = bytes32(uint256(MPC_GROUP_ID) + 3);
        groupId = KeygenStatusHelpers.getGroupId(req);
        assertEq(groupId, MPC_GROUP_ID);
        req = bytes32(uint256(MPC_GROUP_ID) + 4);
        groupId = KeygenStatusHelpers.getGroupId(req);
        assertEq(groupId, MPC_GROUP_ID);
    }

    function testGetKeygenStatus() public {
        bytes32 req = bytes32(uint256(MPC_GROUP_ID) + 1);
        uint8 status = KeygenStatusHelpers.getKeygenStatus(req);
        assertEq(status, 1);
        req = bytes32(uint256(MPC_GROUP_ID) + 2);
        status = KeygenStatusHelpers.getKeygenStatus(req);
        assertEq(status, 2);
        req = bytes32(uint256(MPC_GROUP_ID) + 3);
        status = KeygenStatusHelpers.getKeygenStatus(req);
        assertEq(status, 3);
        req = bytes32(uint256(MPC_GROUP_ID) + 4);
        status = KeygenStatusHelpers.getKeygenStatus(req);
        assertEq(status, 4);
    }
}
