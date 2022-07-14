// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./cheats.sol";
import "./helpers.sol";

import "../interfaces/IMpcManager.sol";
import "../MpcManager.sol";

contract MpcManagerTest is DSTest, Helpers {
    uint256 constant MPC_THRESHOLD = 1;
    bytes32 constant MPC_GROUP_ID = hex"3726383e52fd4cb603498459e8a4a15d148566a51b3f5bfbbf3cac7b61647d04";

    bytes constant MESSAGE_TO_SIGN = bytes("foo");
    uint256 constant STAKE_AMOUNT = 30 ether;
    uint256 constant STAKE_START_TIME = 1640966400; // 2022-01-01
    uint256 constant STAKE_END_TIME = 1642176000; // 2022-01-15

    bytes32 constant UTXO_TX_ID = hex"5245afb3ad9c5c3c9430a7034464f42cee023f228d46ebcae7544759d2779caa";

    address AVALIDO_ADDRESS = 0x1000000000000000000000000000000000000001;

    address RECEIVE_PRINCIPAL_ADDR = 0xd94fC5fd8812ddE061F420D4146bc88e03b6787c;
    address RECEIVE_REWARD_ADDR = 0xe8025f13E6bF0Db21212b0Dd6AEBc4F3d1FB03ce;

    MpcManager mpcManager;
    bytes[] pubKeys = new bytes[](3);

    event ParticipantAdded(bytes indexed publicKey, bytes32 groupId, uint256 index);
    event KeyGenerated(bytes32 indexed groupId, bytes publicKey);
    event SignRequestAdded(uint256 requestId, bytes indexed publicKey, bytes message);
    event SignRequestStarted(uint256 requestId, bytes indexed publicKey, bytes message);
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
    event ExportUTXORequest(bytes32 txId, uint32 outputIndex, address to, bytes indexed genPubKey, uint256[] participantIndices);

    function setUp() public {
        MpcManager _mpcManager = new MpcManager();
        mpcManager = MpcManager(proxyWrapped(address(_mpcManager), ROLE_PROXY_ADMIN));
        mpcManager.initialize();
        mpcManager.setAvaLidoAddress(AVALIDO_ADDRESS);
        mpcManager.setReceivePrincipalAddr(RECEIVE_PRINCIPAL_ADDR);
        mpcManager.setReceiveRewardAddr(RECEIVE_REWARD_ADDR);
        pubKeys[0] = MPC_PLAYER_1_PUBKEY;
        pubKeys[1] = MPC_PLAYER_2_PUBKEY;
        pubKeys[2] = MPC_PLAYER_3_PUBKEY;
    }

    // -------------------------------------------------------------------------
    //  Test cases
    // -------------------------------------------------------------------------

    function testCreateGroup() public {
        cheats.expectEmit(false, false, true, true);
        emit ParticipantAdded(MPC_PLAYER_1_PUBKEY, MPC_GROUP_ID, 1);
        emit ParticipantAdded(MPC_PLAYER_2_PUBKEY, MPC_GROUP_ID, 2);
        emit ParticipantAdded(MPC_PLAYER_3_PUBKEY, MPC_GROUP_ID, 3);
        mpcManager.createGroup(pubKeys, MPC_THRESHOLD);
    }

    function testGetGroup() public {
        setupGroup();
        (bytes[] memory participants, uint256 threshold) = mpcManager.getGroup(MPC_GROUP_ID);
        assertEq0(pubKeys[0], participants[0]);
        assertEq0(pubKeys[1], participants[1]);
        assertEq0(pubKeys[2], participants[2]);
        assertEq(MPC_THRESHOLD, threshold);
    }

    function testReportGeneratedKey() public {
        setupGroup();

        // first participant reports generated key
        cheats.prank(MPC_PLAYER_1_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_GROUP_ID, 1, MPC_GENERATED_PUBKEY);

        // second participant reports generated key
        cheats.prank(MPC_PLAYER_2_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_GROUP_ID, 2, MPC_GENERATED_PUBKEY);

        // event is emitted when the last participant reports generated key
        cheats.expectEmit(false, false, true, true);
        emit KeyGenerated(MPC_GROUP_ID, MPC_GENERATED_PUBKEY);

        cheats.prank(MPC_PLAYER_3_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_GROUP_ID, 3, MPC_GENERATED_PUBKEY);
    }

    function testGetKey() public {
        setupKey();
        IMpcManager.KeyInfo memory keyInfo;
        keyInfo = mpcManager.getKey(MPC_GENERATED_PUBKEY);
        assertEq(MPC_GROUP_ID, keyInfo.groupId);
        assert(keyInfo.confirmed);
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

    function testJoinStakingRequest() public {
        setupStakingRequest();

        cheats.prank(MPC_PLAYER_1_ADDRESS);
        mpcManager.joinRequest(1, 1);

        // Event emitted after required t+1 participants have joined
        cheats.expectEmit(false, false, true, true);
        uint256[] memory indices = new uint256[](2);
        indices[0] = 1;
        indices[1] = 2;
        emit StakeRequestStarted(
            1,
            MPC_GENERATED_PUBKEY,
            indices,
            VALIDATOR_1,
            STAKE_AMOUNT,
            STAKE_START_TIME,
            STAKE_END_TIME
        );
        cheats.prank(MPC_PLAYER_2_ADDRESS);
        mpcManager.joinRequest(1, 2);

        // Cannot join anymore after required t+1 participants have joined
        cheats.prank(MPC_PLAYER_3_ADDRESS);
        cheats.expectRevert(MpcManager.QuorumAlreadyReached.selector);
        mpcManager.joinRequest(1, 3);
    }

    function testReportUTXO() public {
        setupKey();

        // Event ExportUTXORequest emitted for after required t+1 participants have reported the same reward UTXO
        cheats.prank(MPC_PLAYER_1_ADDRESS);
        mpcManager.reportUTXO(MPC_GROUP_ID, 1, MPC_GENERATED_PUBKEY, UTXO_TX_ID, 0);
        cheats.expectEmit(false, false, true, true);
        uint256[] memory indices = new uint256[](2);
        indices[0] = 1;
        indices[1] = 2;
        emit ExportUTXORequest(
            UTXO_TX_ID,
            0,
            RECEIVE_PRINCIPAL_ADDR,
            MPC_GENERATED_PUBKEY,
            indices
        );
        cheats.prank(MPC_PLAYER_2_ADDRESS);
        mpcManager.reportUTXO(MPC_GROUP_ID, 2, MPC_GENERATED_PUBKEY, UTXO_TX_ID, 0);

        // Event ExportUTXORequest emitted for after required t+1 participants have reported the same principal UTXO
        cheats.prank(MPC_PLAYER_3_ADDRESS);
        mpcManager.reportUTXO(MPC_GROUP_ID, 3, MPC_GENERATED_PUBKEY, UTXO_TX_ID, 1);
        cheats.expectEmit(false, false, true, true);
        indices[0] = 3;
        indices[1] = 1;
        emit ExportUTXORequest(
            UTXO_TX_ID,
            0,
            RECEIVE_REWARD_ADDR,
            MPC_GENERATED_PUBKEY,
            indices
        );
        cheats.prank(MPC_PLAYER_1_ADDRESS);
        mpcManager.reportUTXO(MPC_GROUP_ID, 1, MPC_GENERATED_PUBKEY, UTXO_TX_ID, 1);
    }

    // -------------------------------------------------------------------------
    //  Private helper functions
    // -------------------------------------------------------------------------

    function setupGroup() private {
        mpcManager.createGroup(pubKeys, MPC_THRESHOLD);
    }

    function setupKey() private {
        setupGroup();
        cheats.prank(MPC_PLAYER_1_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_GROUP_ID, 1, MPC_GENERATED_PUBKEY);
        cheats.prank(MPC_PLAYER_2_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_GROUP_ID, 2, MPC_GENERATED_PUBKEY);
        cheats.prank(MPC_PLAYER_3_ADDRESS);
        mpcManager.reportGeneratedKey(MPC_GROUP_ID, 3, MPC_GENERATED_PUBKEY);
    }

    function setupStakingRequest() private {
        setupKey();
        cheats.prank(AVALIDO_ADDRESS);
        cheats.deal(AVALIDO_ADDRESS, STAKE_AMOUNT);
        mpcManager.requestStake{value: STAKE_AMOUNT}(VALIDATOR_1, STAKE_AMOUNT, STAKE_START_TIME, STAKE_END_TIME);
    }
}
