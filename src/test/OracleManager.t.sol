// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

// import "ds-test/src/test.sol";
import "ds-test/test.sol";
import "./cheats.sol";
import "./helpers.sol";
import "./console.sol";
import "../OracleManager.sol";
import "../Oracle.sol";
import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";

contract OracleManagerTest is DSTest, Helpers {
    OracleManager oracleManager;
    Oracle oracle;

    event OracleAddressChanged(address oracleAddress);
    event OracleMemberAdded(address member);
    event OracleMemberRemoved(address member);
    event OracleReportSent(uint256 epochId);
    // event RoleOracleManagerChanged(address newRoleOracleManager);
    event WhitelistedValidatorAdded(string nodeId);
    event WhitelistedValidatorRemoved(string nodeId);

    address ORACLE_MANAGER_CONTRACT_ADDRESS;
    address roleOracleManager = 0xf195179eEaE3c8CAB499b5181721e5C57e4769b2; // Wendy the whale gets to manage the oracle 🐳
    string[] whitelistedValidators = [
        "NodeID-P7oB2McjBGgW2NXXWVYjV8JEDFoW9xDE5",
        "NodeID-GWPcbFJZFfZreETSoWjPimr846mXEKCtu",
        "NodeID-NFBbbJ4qCmNaCzeW7sxErhvWqvEQMnYcN"
    ];
    address[] oracleMembers = [
        0x03C1196617387899390d3a98fdBdfD407121BB67,
        0x6C58f6E7DB68D9F75F2E417aCbB67e7Dd4e413bf,
        0xa7bB9405eAF98f36e2683Ba7F36828e260BD0018
    ];
    uint256 epochId = 123456789;
    string fakeNodeId = whitelistedValidators[0];
    string fakeNodeIdTwo = whitelistedValidators[1];
    string unwhitelistedValidator = "NodeId-fakeymcfakerson";
    string newWhitelistedValidator = "NodeId-123";
    address anotherAddressForTesting = 0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2;

    function setUp() public {
        oracleManager = new OracleManager(roleOracleManager, whitelistedValidators, oracleMembers);
        ORACLE_MANAGER_CONTRACT_ADDRESS = address(oracleManager);
        oracle = new Oracle(roleOracleManager, ORACLE_MANAGER_CONTRACT_ADDRESS);
        cheats.prank(roleOracleManager);
        oracleManager.setOracleAddress(address(oracle));
    }

    // -------------------------------------------------------------------------
    //  Report functionality
    // -------------------------------------------------------------------------

    function testReceiveMemberReportWithoutQuorum() public {
        cheats.startPrank(oracleMembers[0]);
        ValidatorData[] memory reportData = new ValidatorData[](1);
        reportData[0].nodeId = fakeNodeId;
        oracleManager.receiveMemberReport(epochId, reportData);
        assertEq(oracleManager.retrieveHashedDataCount(epochId, keccak256(abi.encode(reportData))), 1);
        cheats.stopPrank();
    }

    function testReceiveMemberReportWithQuorum() public {
        cheats.expectEmit(false, false, false, true);
        emit OracleReportSent(epochId);

        ValidatorData[] memory reportDataOne = new ValidatorData[](1);
        reportDataOne[0].nodeId = fakeNodeId;
        ValidatorData[] memory reportDataTwo = new ValidatorData[](1);
        reportDataTwo[0].nodeId = fakeNodeIdTwo;

        cheats.startPrank(oracleMembers[0]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.stopPrank();
        cheats.startPrank(oracleMembers[1]);
        oracleManager.receiveMemberReport(epochId, reportDataTwo);
        cheats.stopPrank();
        cheats.startPrank(oracleMembers[2]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.stopPrank();
    }

    // TODO: function testQuorumWithManyReports() public {}

    function testCannotReportForFinalizedEpoch() public {
        ValidatorData[] memory reportDataOne = new ValidatorData[](1);
        reportDataOne[0].nodeId = fakeNodeId;
        ValidatorData[] memory reportDataTwo = new ValidatorData[](1);
        reportDataTwo[0].nodeId = fakeNodeIdTwo;

        cheats.startPrank(oracleMembers[0]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.stopPrank();
        cheats.startPrank(oracleMembers[1]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.stopPrank();
        cheats.startPrank(oracleMembers[2]);
        cheats.expectRevert(OracleManager.EpochAlreadyFinalized.selector);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.stopPrank();
    }

    function testCannotReportWithUnwhitelistedValidator() public {
        cheats.startPrank(oracleMembers[0]);
        ValidatorData[] memory reportDataOne = new ValidatorData[](3);
        reportDataOne[0].nodeId = fakeNodeId;
        reportDataOne[1].nodeId = unwhitelistedValidator;
        reportDataOne[2].nodeId = fakeNodeIdTwo;
        cheats.expectRevert(OracleManager.ValidatorNodeIdNotFound.selector);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.stopPrank();
    }

    function testOracleCannotReportTwice() public {
        cheats.startPrank(oracleMembers[0]);
        ValidatorData[] memory reportDataOne = new ValidatorData[](1);
        reportDataOne[0].nodeId = fakeNodeId;
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.expectRevert(OracleManager.OracleAlreadyReported.selector);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.stopPrank();
    }

    function testUnauthorizedReceiveMemberReport() public {
        cheats.expectRevert(OracleManager.OracleMemberNotFound.selector);
        ValidatorData[] memory reportData = new ValidatorData[](1);
        reportData[0].nodeId = fakeNodeId;
        oracleManager.receiveMemberReport(epochId, reportData);
    }

    function testCannotReceiveReportWhenPaused() public {
        cheats.prank(roleOracleManager);
        oracleManager.pause();
        cheats.startPrank(oracleMembers[0]);
        ValidatorData[] memory reportDataOne = new ValidatorData[](1);
        reportDataOne[0].nodeId = fakeNodeId;
        cheats.expectRevert("Pausable: paused");
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.stopPrank();
    }

    // -------------------------------------------------------------------------
    //  Oracle management
    // -------------------------------------------------------------------------

    function testAddOracleMember() public {
        cheats.expectEmit(false, false, false, true);
        emit OracleMemberAdded(anotherAddressForTesting);
        cheats.prank(roleOracleManager);
        oracleManager.addOracleMember(anotherAddressForTesting);
        assertEq(oracleManager.oracleMembers(3), anotherAddressForTesting);
    }

    function testUnauthorizedAddOracleMember() public {
        cheats.expectRevert(
            "AccessControl: account 0xb4c79dab8f259c7aee6e5b2aa729821864227e84 is missing role 0x323baab94aa45aaa3cc044271188889aad21b45e0260589722dc9ff769b4b1d8"
        );
        oracleManager.addOracleMember(anotherAddressForTesting);
    }

    function testCannotAddOracleMemberAgain() public {
        cheats.startPrank(roleOracleManager);
        cheats.expectRevert(OracleManager.OracleMemberExists.selector);
        oracleManager.addOracleMember(oracleMembers[0]);
        cheats.stopPrank();
    }

    function testRemoveOracleMember() public {
        cheats.expectEmit(false, false, false, true);
        emit OracleMemberRemoved(oracleMembers[2]);
        cheats.startPrank(roleOracleManager);
        oracleManager.removeOracleMember(oracleMembers[2]);
    }

    function testUnauthorizedRemoveOracleMember() public {
        cheats.expectRevert(
            "AccessControl: account 0xb4c79dab8f259c7aee6e5b2aa729821864227e84 is missing role 0x323baab94aa45aaa3cc044271188889aad21b45e0260589722dc9ff769b4b1d8"
        );
        oracleManager.removeOracleMember(anotherAddressForTesting);
    }

    function testCannotRemoveOracleMemberIfNotPresent() public {
        cheats.expectRevert(OracleManager.OracleMemberNotFound.selector);
        cheats.startPrank(roleOracleManager);
        oracleManager.removeOracleMember(0xf195179eEaE3c8CAB499b5181721e5C57e4769b2);
        cheats.stopPrank();
    }

    // -------------------------------------------------------------------------
    //  Validator management
    // -------------------------------------------------------------------------

    function testAddWhitelistedValidator() public {
        cheats.expectEmit(false, false, false, true);
        emit WhitelistedValidatorAdded(newWhitelistedValidator);
        cheats.prank(roleOracleManager);
        oracleManager.addWhitelistedValidator(newWhitelistedValidator);
        assertEq(oracleManager.whitelistedValidators(3), newWhitelistedValidator);
    }

    function testUnauthorizedAddWhitelistedValidator() public {
        cheats.expectRevert(
            "AccessControl: account 0xb4c79dab8f259c7aee6e5b2aa729821864227e84 is missing role 0x323baab94aa45aaa3cc044271188889aad21b45e0260589722dc9ff769b4b1d8"
        );
        oracleManager.addWhitelistedValidator(newWhitelistedValidator);
    }

    function testCannotAddWhitelistedValidatorAgain() public {
        cheats.startPrank(roleOracleManager);
        cheats.expectRevert(OracleManager.ValidatorAlreadyWhitelisted.selector);
        oracleManager.addWhitelistedValidator(whitelistedValidators[0]);
        cheats.stopPrank();
    }

    function testRemoveWhitelistedValidator() public {
        cheats.expectEmit(false, false, false, true);
        emit WhitelistedValidatorRemoved(whitelistedValidators[2]);
        cheats.startPrank(roleOracleManager);
        oracleManager.removeWhitelistedValidator(whitelistedValidators[2]);
    }

    function testUnauthorizedRemoveWhitelistedValidator() public {
        cheats.expectRevert(
            "AccessControl: account 0xb4c79dab8f259c7aee6e5b2aa729821864227e84 is missing role 0x323baab94aa45aaa3cc044271188889aad21b45e0260589722dc9ff769b4b1d8"
        );
        oracleManager.removeWhitelistedValidator(whitelistedValidators[0]);
    }

    function testCannotRemoveWhitelistedValidatorIfNotPresent() public {
        cheats.expectRevert(OracleManager.ValidatorNodeIdNotFound.selector);
        cheats.startPrank(roleOracleManager);
        oracleManager.removeWhitelistedValidator(unwhitelistedValidator);
        cheats.stopPrank();
    }

    // -------------------------------------------------------------------------
    //  Address and auth management
    // -------------------------------------------------------------------------

    function testSetOracleAddress() public {
        cheats.expectEmit(false, false, false, true);
        emit OracleAddressChanged(anotherAddressForTesting);
        cheats.prank(roleOracleManager);
        oracleManager.setOracleAddress(anotherAddressForTesting);
    }

    function testUnauthorizedSetOracleAddress() public {
        cheats.expectRevert(
            "AccessControl: account 0xb4c79dab8f259c7aee6e5b2aa729821864227e84 is missing role 0x323baab94aa45aaa3cc044271188889aad21b45e0260589722dc9ff769b4b1d8"
        );
        oracleManager.setOracleAddress(anotherAddressForTesting);
    }

    // TODO: write and test changing ROLE_ORACLE_MANAGER
}
