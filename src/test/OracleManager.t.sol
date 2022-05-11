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

    string[] WHITELISTED_VALIDATORS = [WHITELISTED_VALIDATOR_1, WHITELISTED_VALIDATOR_2, WHITELISTED_VALIDATOR_3];
    address[] ORACLE_MEMBERS = [
        WHITELISTED_ORACLE_1,
        WHITELISTED_ORACLE_2,
        WHITELISTED_ORACLE_3,
        WHITELISTED_ORACLE_4,
        WHITELISTED_ORACLE_5
    ];
    uint256 epochId = 123456789;
    string fakeNodeId = WHITELISTED_VALIDATORS[0];
    string fakeNodeIdTwo = WHITELISTED_VALIDATORS[1];
    string unwhitelistedValidator = "NodeId-fakeymcfakerson";
    string newWhitelistedValidator = "NodeId-123";
    address anotherAddressForTesting = 0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2;

    function setUp() public {
        oracleManager = new OracleManager(ROLE_ORACLE_MANAGER, WHITELISTED_VALIDATORS, ORACLE_MEMBERS);
        ORACLE_MANAGER_CONTRACT_ADDRESS = address(oracleManager);
        oracle = new Oracle(ROLE_ORACLE_MANAGER, ORACLE_MANAGER_CONTRACT_ADDRESS);
        cheats.prank(ROLE_ORACLE_MANAGER);
        oracleManager.setOracleAddress(address(oracle));
    }

    // -------------------------------------------------------------------------
    //  Report functionality
    // -------------------------------------------------------------------------

    function testReceiveMemberReportWithoutQuorum() public {
        cheats.startPrank(ORACLE_MEMBERS[0]);
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

        cheats.startPrank(ORACLE_MEMBERS[0]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.stopPrank();
        cheats.startPrank(ORACLE_MEMBERS[1]);
        oracleManager.receiveMemberReport(epochId, reportDataTwo);
        cheats.stopPrank();
        cheats.startPrank(ORACLE_MEMBERS[2]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.stopPrank();
        cheats.startPrank(ORACLE_MEMBERS[3]);
        oracleManager.receiveMemberReport(epochId, reportDataTwo);
        cheats.stopPrank();
        cheats.startPrank(ORACLE_MEMBERS[4]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.stopPrank();
    }

    function testCannotReportForFinalizedEpoch() public {
        ValidatorData[] memory reportDataOne = new ValidatorData[](1);
        reportDataOne[0].nodeId = fakeNodeId;
        ValidatorData[] memory reportDataTwo = new ValidatorData[](1);
        reportDataTwo[0].nodeId = fakeNodeIdTwo;

        cheats.startPrank(ORACLE_MEMBERS[0]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.stopPrank();
        cheats.startPrank(ORACLE_MEMBERS[1]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.stopPrank();
        cheats.startPrank(ORACLE_MEMBERS[2]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.stopPrank();
        cheats.startPrank(ORACLE_MEMBERS[3]);
        cheats.expectRevert(OracleManager.EpochAlreadyFinalized.selector);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.stopPrank();
    }

    function testCannotReportWithUnwhitelistedValidator() public {
        cheats.startPrank(ORACLE_MEMBERS[0]);
        ValidatorData[] memory reportDataOne = new ValidatorData[](3);
        reportDataOne[0].nodeId = fakeNodeId;
        reportDataOne[1].nodeId = unwhitelistedValidator;
        reportDataOne[2].nodeId = fakeNodeIdTwo;
        cheats.expectRevert(OracleManager.ValidatorNodeIdNotFound.selector);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.stopPrank();
    }

    function testOracleCannotReportTwice() public {
        cheats.startPrank(ORACLE_MEMBERS[0]);
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
        cheats.prank(ROLE_ORACLE_MANAGER);
        oracleManager.pause();
        cheats.startPrank(ORACLE_MEMBERS[0]);
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
        cheats.prank(ROLE_ORACLE_MANAGER);
        oracleManager.addOracleMember(anotherAddressForTesting);

        // Assert it exists in the whitelist array
        address[] memory whitelistedOraclesArrayFromContract = oracleManager.getWhitelistedOracles();
        assertTrue(addressArrayContains(anotherAddressForTesting, whitelistedOraclesArrayFromContract));
        // Assert it exists in the whitelist mapping
        assertTrue(oracleManager.whitelistedOraclesMapping(anotherAddressForTesting));
    }

    function testUnauthorizedAddOracleMember() public {
        cheats.expectRevert(
            "AccessControl: account 0xb4c79dab8f259c7aee6e5b2aa729821864227e84 is missing role 0x323baab94aa45aaa3cc044271188889aad21b45e0260589722dc9ff769b4b1d8"
        );
        oracleManager.addOracleMember(anotherAddressForTesting);
    }

    function testCannotAddOracleMemberAgain() public {
        cheats.startPrank(ROLE_ORACLE_MANAGER);
        cheats.expectRevert(OracleManager.OracleMemberExists.selector);
        oracleManager.addOracleMember(ORACLE_MEMBERS[0]);
        cheats.stopPrank();
    }

    function testRemoveOracleMember() public {
        cheats.expectEmit(false, false, false, true);
        emit OracleMemberRemoved(ORACLE_MEMBERS[2]);
        cheats.startPrank(ROLE_ORACLE_MANAGER);
        oracleManager.removeOracleMember(ORACLE_MEMBERS[2]);

        // Assert it doesn't exist in the whitelist array
        address[] memory whitelistedOraclesArrayFromContract = oracleManager.getWhitelistedOracles();
        assertTrue(!addressArrayContains(anotherAddressForTesting, whitelistedOraclesArrayFromContract));
        // Assert it doesn't exist in the whitelist mapping
        assertTrue(!oracleManager.whitelistedOraclesMapping(anotherAddressForTesting));
    }

    function testUnauthorizedRemoveOracleMember() public {
        cheats.expectRevert(
            "AccessControl: account 0xb4c79dab8f259c7aee6e5b2aa729821864227e84 is missing role 0x323baab94aa45aaa3cc044271188889aad21b45e0260589722dc9ff769b4b1d8"
        );
        oracleManager.removeOracleMember(anotherAddressForTesting);
    }

    function testCannotRemoveOracleMemberIfNotPresent() public {
        cheats.expectRevert(OracleManager.OracleMemberNotFound.selector);
        cheats.startPrank(ROLE_ORACLE_MANAGER);
        oracleManager.removeOracleMember(0xf195179eEaE3c8CAB499b5181721e5C57e4769b2);
        cheats.stopPrank();
    }

    // -------------------------------------------------------------------------
    //  Validator management
    // -------------------------------------------------------------------------

    function testAddWhitelistedValidator() public {
        cheats.expectEmit(false, false, false, true);
        emit WhitelistedValidatorAdded(newWhitelistedValidator);
        cheats.prank(ROLE_ORACLE_MANAGER);
        oracleManager.addWhitelistedValidator(newWhitelistedValidator);

        // Assert it exists in the whitelist array
        string[] memory whitelistedValidatorsArrayFromContract = oracleManager.getWhitelistedValidators();
        assertTrue(stringArrayContains(newWhitelistedValidator, whitelistedValidatorsArrayFromContract));
        // Assert it exists in the whitelist mapping
        assertTrue(oracleManager.whitelistedValidatorsMapping(newWhitelistedValidator));
    }

    function testUnauthorizedAddWhitelistedValidator() public {
        cheats.expectRevert(
            "AccessControl: account 0xb4c79dab8f259c7aee6e5b2aa729821864227e84 is missing role 0x323baab94aa45aaa3cc044271188889aad21b45e0260589722dc9ff769b4b1d8"
        );
        oracleManager.addWhitelistedValidator(newWhitelistedValidator);
    }

    function testCannotAddWhitelistedValidatorAgain() public {
        cheats.startPrank(ROLE_ORACLE_MANAGER);
        cheats.expectRevert(OracleManager.ValidatorAlreadyWhitelisted.selector);
        oracleManager.addWhitelistedValidator(WHITELISTED_VALIDATORS[0]);
        cheats.stopPrank();
    }

    function testRemoveWhitelistedValidator() public {
        cheats.expectEmit(false, false, false, true);
        emit WhitelistedValidatorRemoved(WHITELISTED_VALIDATORS[2]);
        cheats.startPrank(ROLE_ORACLE_MANAGER);
        oracleManager.removeWhitelistedValidator(WHITELISTED_VALIDATORS[2]);

        // Assert it doesn't exist in the whitelist array
        string[] memory whitelistedValidatorsArrayFromContract = oracleManager.getWhitelistedValidators();
        assertTrue(!stringArrayContains(newWhitelistedValidator, whitelistedValidatorsArrayFromContract));
        // Assert it doesn't exist in the whitelist mapping
        assertTrue(!oracleManager.whitelistedValidatorsMapping(newWhitelistedValidator));
    }

    function testUnauthorizedRemoveWhitelistedValidator() public {
        cheats.expectRevert(
            "AccessControl: account 0xb4c79dab8f259c7aee6e5b2aa729821864227e84 is missing role 0x323baab94aa45aaa3cc044271188889aad21b45e0260589722dc9ff769b4b1d8"
        );
        oracleManager.removeWhitelistedValidator(WHITELISTED_VALIDATORS[0]);
    }

    function testCannotRemoveWhitelistedValidatorIfNotPresent() public {
        cheats.expectRevert(OracleManager.ValidatorNodeIdNotFound.selector);
        cheats.startPrank(ROLE_ORACLE_MANAGER);
        oracleManager.removeWhitelistedValidator(unwhitelistedValidator);
        cheats.stopPrank();
    }

    // -------------------------------------------------------------------------
    //  Address and auth management
    // -------------------------------------------------------------------------

    function testSetOracleAddress() public {
        cheats.expectEmit(false, false, false, true);
        emit OracleAddressChanged(anotherAddressForTesting);
        cheats.prank(ROLE_ORACLE_MANAGER);
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
