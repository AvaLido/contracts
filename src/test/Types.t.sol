// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "./helpers.sol";
import "../Types.sol";

contract ValidatorHelpersTest is Test, Helpers {
    function setUp() public {}

    function testHasUptime() public {
        uint24 withSet24 = 0 | (1 << 23);
        bool res = ValidatorHelpers.hasAcceptableUptime(Validator.wrap(withSet24));
        assertTrue(res);
    }

    function testHasUptimeFalse() public {
        uint24 data = 1;
        bool res = ValidatorHelpers.hasAcceptableUptime(Validator.wrap(data));
        assertTrue(!res);
    }

    function testHasTimeRemaining() public {
        uint24 data = 0;
        uint24 withSet23 = data | (1 << 22);
        bool res = ValidatorHelpers.hasTimeRemaining(Validator.wrap(withSet23));
        assertTrue(res);
    }

    function testHasTimeRemainingFalse() public {
        uint24 data = 0;
        bool res = ValidatorHelpers.hasTimeRemaining(Validator.wrap(data));
        assertTrue(!res);
    }

    function testHasTimeRemainingFalseWhenUptimeSet() public {
        uint24 data = 0 | (1 << 23); // set bit 8 (uptime bit)
        bool res = ValidatorHelpers.hasTimeRemaining(Validator.wrap(data));
        assertTrue(!res);
    }

    function testGetNodeIndexOne() public {
        uint24 one = 0 | (1 << 10); // Set first bit of index
        uint256 res = ValidatorHelpers.getNodeIndex(Validator.wrap(one));
        assertEq(res, 1);
    }

    function testGetNodeIndexWithFuzzing(uint24 x) public {
        vm.assume(x < 4096);
        uint24 data = x << 10;
        uint256 res = ValidatorHelpers.getNodeIndex(Validator.wrap(data));
        assertEq(res, x);
    }

    function testFreeSpaceZero() public {
        uint24 data = 0;
        uint256 space = ValidatorHelpers.freeSpace(Validator.wrap(data));
        assertEq(space, 0);
    }

    function testFreeSpace() public {
        uint24 data = 0 | (42);
        uint256 space = ValidatorHelpers.freeSpace(Validator.wrap(data));
        assertEq(space, 42 * 100 ether);
    }

    function testPackRoundTrip() public {
        Validator val = ValidatorHelpers.packValidator(129, true, false, 1);
        assertEq(ValidatorHelpers.getNodeIndex(val), 129);
        assertTrue(ValidatorHelpers.hasAcceptableUptime(val));
        assertTrue(!ValidatorHelpers.hasTimeRemaining(val));
        assertEq(ValidatorHelpers.freeSpace(val), 1 * 100 ether);
    }
}

contract IdHelpersTest is DSTest, Helpers {
    function setUp() public {}

    function testMakeGroupId() public {
        bytes32 groupId = IdHelpers.makeGroupId(MPC_GROUP_HASH, 3, 1);
        assertEq(groupId, MPC_GROUP_ID);
    }

    function testMakeParticipantId() public {
        bytes32 participantId = IdHelpers.makeParticipantId(MPC_GROUP_ID, 1);
        assertEq(participantId, MPC_PARTICIPANT1_ID);
        participantId = IdHelpers.makeParticipantId(MPC_GROUP_ID, 2);
        assertEq(participantId, MPC_PARTICIPANT2_ID);
        participantId = IdHelpers.makeParticipantId(MPC_GROUP_ID, 3);
        assertEq(participantId, MPC_PARTICIPANT3_ID);
    }

    function testGetGroupSize() public {
        uint8 groupSize = IdHelpers.getGroupSize(MPC_GROUP_ID);
        assertEq(groupSize, 3);
        groupSize = IdHelpers.getGroupSize(MPC_PARTICIPANT1_ID);
        assertEq(groupSize, 3);
        groupSize = IdHelpers.getGroupSize(MPC_PARTICIPANT2_ID);
        assertEq(groupSize, 3);
        groupSize = IdHelpers.getGroupSize(MPC_PARTICIPANT3_ID);
        assertEq(groupSize, 3);
    }

    function testGetThreshold() public {
        uint8 threshold = IdHelpers.getThreshold(MPC_GROUP_ID);
        assertEq(threshold, 1);
        threshold = IdHelpers.getThreshold(MPC_PARTICIPANT1_ID);
        assertEq(threshold, 1);
        threshold = IdHelpers.getThreshold(MPC_PARTICIPANT2_ID);
        assertEq(threshold, 1);
        threshold = IdHelpers.getThreshold(MPC_PARTICIPANT3_ID);
        assertEq(threshold, 1);
    }

    function testGetGroupId() public {
        bytes32 groupId = IdHelpers.getGroupId(MPC_PARTICIPANT1_ID);
        assertEq(groupId, MPC_GROUP_ID);
        groupId = IdHelpers.getGroupId(MPC_PARTICIPANT2_ID);
        assertEq(groupId, MPC_GROUP_ID);
        groupId = IdHelpers.getGroupId(MPC_PARTICIPANT3_ID);
        assertEq(groupId, MPC_GROUP_ID);
    }

    function testGetParticipantIndex() public {
        uint8 participantIndex = IdHelpers.getParticipantIndex(MPC_PARTICIPANT1_ID);
        assertEq(participantIndex, 1);
        participantIndex = IdHelpers.getParticipantIndex(MPC_PARTICIPANT2_ID);
        assertEq(participantIndex, 2);
        participantIndex = IdHelpers.getParticipantIndex(MPC_PARTICIPANT3_ID);
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

    function testGetIndices() public {
        uint256 indices = ConfirmationHelpers.getIndices(uint256(CONFIRMATION));
        assertEq(indices, uint256(INDICES));
    }

    function testGetConfirmationCount() public {
        uint8 count = ConfirmationHelpers.getConfirmationCount(uint256(CONFIRMATION));
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
