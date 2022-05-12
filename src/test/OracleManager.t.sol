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
    }

    // -------------------------------------------------------------------------
    //  Initialization
    // -------------------------------------------------------------------------

    function testOracleContractAddressNotSet() public {
        ValidatorData[] memory reportData = new ValidatorData[](1);
        reportData[0].nodeId = fakeNodeId;
        cheats.prank(ORACLE_MEMBERS[0]);
        cheats.expectRevert(OracleManager.OracleContractAddressNotSet.selector);
        oracleManager.receiveMemberReport(epochId, reportData);
        cheats.prank(ROLE_ORACLE_MANAGER);
        oracleManager.setOracleAddress(address(oracle));
        address oracleAddressFromContract = oracleManager.getOracleAddress();
        cheats.prank(ORACLE_MEMBERS[0]);
        oracleManager.receiveMemberReport(epochId, reportData);
        assertEq(oracleManager.retrieveHashedDataCount(epochId, keccak256(abi.encode(reportData))), 1);
    }

    // -------------------------------------------------------------------------
    //  Report functionality
    // -------------------------------------------------------------------------

    function testReceiveMemberReportWithoutQuorum() public {
        cheats.prank(ROLE_ORACLE_MANAGER);
        oracleManager.setOracleAddress(address(oracle));
        ValidatorData[] memory reportData = new ValidatorData[](1);
        reportData[0].nodeId = fakeNodeId;
        cheats.prank(ORACLE_MEMBERS[0]);
        oracleManager.receiveMemberReport(epochId, reportData);
    }

    function testReceiveMemberReportWithQuorum() public {
        cheats.prank(ROLE_ORACLE_MANAGER);
        oracleManager.setOracleAddress(address(oracle));

        ValidatorData[] memory reportDataOne = new ValidatorData[](1);
        reportDataOne[0].nodeId = fakeNodeId;
        ValidatorData[] memory reportDataTwo = new ValidatorData[](1);
        reportDataTwo[0].nodeId = fakeNodeIdTwo;

        cheats.prank(ORACLE_MEMBERS[0]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.prank(ORACLE_MEMBERS[1]);
        oracleManager.receiveMemberReport(epochId, reportDataTwo);
        cheats.prank(ORACLE_MEMBERS[2]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.prank(ORACLE_MEMBERS[3]);
        oracleManager.receiveMemberReport(epochId, reportDataTwo);
        cheats.prank(ORACLE_MEMBERS[4]);
        cheats.expectEmit(false, false, false, true);
        emit OracleReportSent(epochId);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
    }

    function testCannotReportForFinalizedEpoch() public {
        cheats.prank(ROLE_ORACLE_MANAGER);
        oracleManager.setOracleAddress(address(oracle));

        ValidatorData[] memory reportDataOne = new ValidatorData[](1);
        reportDataOne[0].nodeId = fakeNodeId;
        ValidatorData[] memory reportDataTwo = new ValidatorData[](1);
        reportDataTwo[0].nodeId = fakeNodeIdTwo;

        cheats.prank(ORACLE_MEMBERS[0]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.prank(ORACLE_MEMBERS[1]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.prank(ORACLE_MEMBERS[2]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.prank(ORACLE_MEMBERS[3]);
        cheats.expectRevert(OracleManager.EpochAlreadyFinalized.selector);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
    }

    function testCannotReportWithUnwhitelistedValidator() public {
        cheats.prank(ROLE_ORACLE_MANAGER);
        oracleManager.setOracleAddress(address(oracle));

        ValidatorData[] memory reportDataOne = new ValidatorData[](3);
        reportDataOne[0].nodeId = fakeNodeId;
        reportDataOne[1].nodeId = unwhitelistedValidator;
        reportDataOne[2].nodeId = fakeNodeIdTwo;
        cheats.prank(ORACLE_MEMBERS[0]);
        cheats.expectRevert(OracleManager.ValidatorNodeIdNotFound.selector);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
    }

    function testOracleCannotReportTwice() public {
        cheats.prank(ROLE_ORACLE_MANAGER);
        oracleManager.setOracleAddress(address(oracle));

        ValidatorData[] memory reportDataOne = new ValidatorData[](1);
        reportDataOne[0].nodeId = fakeNodeId;
        cheats.startPrank(ORACLE_MEMBERS[0]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.expectRevert(OracleManager.OracleAlreadyReported.selector);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.stopPrank();
    }

    function testUnauthorizedReceiveMemberReport() public {
        cheats.prank(ROLE_ORACLE_MANAGER);
        oracleManager.setOracleAddress(address(oracle));

        ValidatorData[] memory reportData = new ValidatorData[](1);
        reportData[0].nodeId = fakeNodeId;
        cheats.expectRevert(OracleManager.OracleMemberNotFound.selector);
        oracleManager.receiveMemberReport(epochId, reportData);
    }

    function testCannotReceiveReportWhenPaused() public {
        cheats.prank(ROLE_ORACLE_MANAGER);
        oracleManager.pause();
        ValidatorData[] memory reportDataOne = new ValidatorData[](1);
        reportDataOne[0].nodeId = fakeNodeId;
        cheats.prank(ORACLE_MEMBERS[0]);
        cheats.expectRevert("Pausable: paused");
        oracleManager.receiveMemberReport(epochId, reportDataOne);
    }

    // -------------------------------------------------------------------------
    //  Oracle management
    // -------------------------------------------------------------------------

    function testAddOracleMember() public {
        cheats.prank(ROLE_ORACLE_MANAGER);
        cheats.expectEmit(false, false, false, true);
        emit OracleMemberAdded(anotherAddressForTesting);
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
        cheats.prank(ROLE_ORACLE_MANAGER);
        cheats.expectRevert(OracleManager.OracleMemberExists.selector);
        oracleManager.addOracleMember(ORACLE_MEMBERS[0]);
    }

    function testRemoveOracleMember() public {
        cheats.prank(ROLE_ORACLE_MANAGER);
        cheats.expectEmit(false, false, false, true);
        emit OracleMemberRemoved(ORACLE_MEMBERS[2]);
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
        cheats.prank(ROLE_ORACLE_MANAGER);
        cheats.expectRevert(OracleManager.OracleMemberNotFound.selector);
        oracleManager.removeOracleMember(0xf195179eEaE3c8CAB499b5181721e5C57e4769b2);
    }

    // -------------------------------------------------------------------------
    //  Validator management
    // -------------------------------------------------------------------------

    function testAddWhitelistedValidator() public {
        cheats.prank(ROLE_ORACLE_MANAGER);
        cheats.expectEmit(false, false, false, true);
        emit WhitelistedValidatorAdded(newWhitelistedValidator);
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
        cheats.prank(ROLE_ORACLE_MANAGER);
        cheats.expectRevert(OracleManager.ValidatorAlreadyWhitelisted.selector);
        oracleManager.addWhitelistedValidator(WHITELISTED_VALIDATORS[0]);
    }

    function testRemoveWhitelistedValidator() public {
        cheats.prank(ROLE_ORACLE_MANAGER);
        cheats.expectEmit(false, false, false, true);
        emit WhitelistedValidatorRemoved(WHITELISTED_VALIDATORS[2]);
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
        cheats.prank(ROLE_ORACLE_MANAGER);
        cheats.expectRevert(OracleManager.ValidatorNodeIdNotFound.selector);
        oracleManager.removeWhitelistedValidator(unwhitelistedValidator);
    }

    // -------------------------------------------------------------------------
    //  Address and auth management
    // -------------------------------------------------------------------------

    function testSetOracleAddress() public {
        cheats.prank(ROLE_ORACLE_MANAGER);
        cheats.expectEmit(false, false, false, true);
        emit OracleAddressChanged(anotherAddressForTesting);
        oracleManager.setOracleAddress(anotherAddressForTesting);
    }

    function testUnauthorizedSetOracleAddress() public {
        cheats.expectRevert(
            "AccessControl: account 0xb4c79dab8f259c7aee6e5b2aa729821864227e84 is missing role 0x323baab94aa45aaa3cc044271188889aad21b45e0260589722dc9ff769b4b1d8"
        );
        oracleManager.setOracleAddress(anotherAddressForTesting);
    }

    // TODO: write and test changing ROLE_ORACLE_MANAGER

    // -------------------------------------------------------------------------
    //  TEMPORARY FUNCTION TEST - REMOVE WHEN FUNCTION IS REMOVED
    // -------------------------------------------------------------------------

    function testTemporaryFinalizeReport() public {
        cheats.prank(ROLE_ORACLE_MANAGER);
        oracleManager.setOracleAddress(address(oracle));

        ValidatorData[] memory reportData = new ValidatorData[](2);
        reportData[0].nodeId = fakeNodeId;
        reportData[0].stakeEndTime = 123456789;
        reportData[0].freeSpace = 800000;
        reportData[1].nodeId = fakeNodeIdTwo;
        reportData[1].stakeEndTime = 123456789;
        reportData[1].freeSpace = 500000;

        cheats.prank(ORACLE_MEMBERS[0]);
        cheats.expectEmit(false, false, false, true);
        emit OracleReportSent(epochId);
        oracleManager.temporaryFinalizeReport(epochId, reportData);
    }
}
