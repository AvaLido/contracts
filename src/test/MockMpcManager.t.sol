// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

import "./helpers.sol";

import "../interfaces/IMpcManager.sol";
import "../MockMpcManager.sol";

contract MockMpcManagerTest is Test, Helpers {
    uint8 constant MPC_THRESHOLD = 1;
    bytes32 constant MPC_BIG_GROUP_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c0900";
    bytes32 constant MPC_BIG_P01_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c0901";
    bytes32 constant MPC_BIG_P02_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c0902";
    bytes32 constant MPC_BIG_P03_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c0903";
    bytes32 constant MPC_BIG_P04_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c0904";
    bytes32 constant MPC_BIG_P05_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c0905";
    bytes32 constant MPC_BIG_P06_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c0906";
    bytes32 constant MPC_BIG_P07_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c0907";
    bytes32 constant MPC_BIG_P08_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c0908";
    bytes32 constant MPC_BIG_P09_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c0909";
    bytes32 constant MPC_BIG_P10_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c090a";
    bytes32 constant MPC_BIG_P11_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c090b";
    bytes32 constant MPC_BIG_P12_ID = hex"270b05bac4f59f0c069249ee5d68364fc56b326bf6d63b8d5577fcd8c20c090c";
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

    MockMpcManager mpcManager;
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
    event RequestStarted(bytes32 requestHash, uint256 participantIndices);
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

    function setUp() public {
        mpcManager = new MockMpcManager();
    }

    // -------------------------------------------------------------------------
    //  Test cases
    // -------------------------------------------------------------------------
  
    function testAddParticipant() public {
        vm.expectEmit(false, false, true, true);
        emit ParticipantAdded(MPC_BIG_P01_PUBKEY, MPC_BIG_GROUP_ID, 1);

        vm.prank(MPC_BIG_P01_ADDRESS);
        mpcManager.addParticipant(MPC_BIG_P01_PUBKEY, MPC_BIG_GROUP_ID, 1);
    }

    function testAddKey() public {
        vm.expectEmit(false, false, true, true);
        emit KeyGenerated(MPC_BIG_GROUP_ID, MPC_GENERATED_PUBKEY);

        vm.prank(MPC_BIG_P12_ADDRESS);
        mpcManager.addKey(MPC_BIG_GROUP_ID, MPC_GENERATED_PUBKEY);
    }
    function testAddStakeRequest() public {
        vm.expectEmit(false, false, true, true);
        emit StakeRequestAdded(1, MPC_GENERATED_PUBKEY, "abc", 100 ether, 1, 2);

        vm.prank(MPC_BIG_P12_ADDRESS);
        mpcManager.addStakeRequest(1, MPC_GENERATED_PUBKEY, "abc", 100 ether, 1, 2);
    }
    function testStartRequest() public {
        vm.expectEmit(false, false, true, true);
        emit RequestStarted(bytes32(uint256(1)), 1);

        vm.prank(MPC_BIG_P12_ADDRESS);
        mpcManager.startRequest(bytes32(uint256(1)), 1);
    }
}
