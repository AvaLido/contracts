// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./cheats.sol";
import "./helpers.sol";

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

    address[] ORACLE_MEMBERS = [
        WHITELISTED_ORACLE_1,
        WHITELISTED_ORACLE_2,
        WHITELISTED_ORACLE_3,
        WHITELISTED_ORACLE_4,
        WHITELISTED_ORACLE_5
    ];
    uint256 epochId = 123456789;
    // string fakeNodeId = VALIDATOR_1;
    // string fakeNodeIdTwo = VALIDATOR_2;
    address anotherAddressForTesting = 0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2;
    string[] nodeIds;

    function setUp() public {
        OracleManager _oracleManager = new OracleManager();
        oracleManager = OracleManager(proxyWrapped(address(_oracleManager), ROLE_PROXY_ADMIN));
        oracleManager.initialize(ORACLE_ADMIN_ADDRESS, ORACLE_MEMBERS);

        Oracle _oracle = new Oracle();
        oracle = Oracle(proxyWrapped(address(_oracle), ROLE_PROXY_ADMIN));
        oracle.initialize(ORACLE_ADMIN_ADDRESS, address(oracleManager));

        // string[] storage nodeIds;
        nodeIds.push("Node-0");
        // nodeIds[1] = "Node-1";
        oracle.setNodeIDList(nodeIds);
    }

    // -------------------------------------------------------------------------
    //  Initialization
    // -------------------------------------------------------------------------

    function testOracleContractAddressNotSet() public {
        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, true, true, 100);

        cheats.prank(ORACLE_MEMBERS[0]);
        cheats.expectRevert(OracleManager.OracleContractAddressNotSet.selector);
        oracleManager.receiveMemberReport(epochId, reportData);

        cheats.prank(ORACLE_ADMIN_ADDRESS);
        oracleManager.setOracleAddress(address(oracle));
        cheats.prank(ORACLE_MEMBERS[0]);
        oracleManager.receiveMemberReport(epochId, reportData);
        assertEq(oracleManager.retrieveHashedDataCount(epochId, keccak256(abi.encode(reportData))), 1);
    }

    // -------------------------------------------------------------------------
    //  Report functionality
    // -------------------------------------------------------------------------

    function testReceiveMemberReportWithoutQuorum() public {
        cheats.prank(ORACLE_ADMIN_ADDRESS);
        oracleManager.setOracleAddress(address(oracle));

        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, true, true, 100);
        cheats.prank(ORACLE_MEMBERS[0]);
        oracleManager.receiveMemberReport(epochId, reportData);
    }

    function testReceiveMemberReportWithQuorum() public {
        cheats.prank(ORACLE_ADMIN_ADDRESS);
        oracleManager.setOracleAddress(address(oracle));

        Validator[] memory reportDataOne = new Validator[](1);
        reportDataOne[0] = ValidatorHelpers.packValidator(0, true, true, 100);
        Validator[] memory reportDataTwo = new Validator[](1);
        reportDataTwo[0] = ValidatorHelpers.packValidator(1, true, true, 200);

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
        cheats.prank(ORACLE_ADMIN_ADDRESS);
        oracleManager.setOracleAddress(address(oracle));

        Validator[] memory reportDataOne = new Validator[](1);
        reportDataOne[0] = ValidatorHelpers.packValidator(0, true, true, 100);
        Validator[] memory reportDataTwo = new Validator[](1);
        reportDataTwo[0] = ValidatorHelpers.packValidator(1, true, true, 200);

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

    function testOracleCannotReportTwice() public {
        cheats.prank(ORACLE_ADMIN_ADDRESS);
        oracleManager.setOracleAddress(address(oracle));

        Validator[] memory reportDataOne = new Validator[](1);
        reportDataOne[0] = ValidatorHelpers.packValidator(0, true, true, 100);
        cheats.startPrank(ORACLE_MEMBERS[0]);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.expectRevert(OracleManager.OracleAlreadyReported.selector);
        oracleManager.receiveMemberReport(epochId, reportDataOne);
        cheats.stopPrank();
    }

    function testUnauthorizedReceiveMemberReport() public {
        cheats.prank(ORACLE_ADMIN_ADDRESS);
        oracleManager.setOracleAddress(address(oracle));

        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, true, true, 100);
        cheats.expectRevert(OracleManager.OracleMemberNotFound.selector);
        oracleManager.receiveMemberReport(epochId, reportData);
    }

    function testCannotReceiveReportWhenPaused() public {
        cheats.prank(ORACLE_ADMIN_ADDRESS);
        oracleManager.pause();
        Validator[] memory reportDataOne = new Validator[](1);
        reportDataOne[0] = ValidatorHelpers.packValidator(0, true, true, 100);
        cheats.prank(ORACLE_MEMBERS[0]);
        cheats.expectRevert("Pausable: paused");
        oracleManager.receiveMemberReport(epochId, reportDataOne);
    }

    // function testReportWithInvalidIndex() public {
    //     cheats.prank(ORACLE_ADMIN_ADDRESS);
    //     oracleManager.setOracleAddress(address(oracle));
    // }

    // -------------------------------------------------------------------------
    //  Oracle management
    // -------------------------------------------------------------------------

    function testAddOracleMember() public {
        cheats.prank(ORACLE_ADMIN_ADDRESS);
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
            "AccessControl: account 0x62d69f6867a0a084c6d313943dc22023bc263691 is missing role 0x323baab94aa45aaa3cc044271188889aad21b45e0260589722dc9ff769b4b1d8"
        );
        oracleManager.addOracleMember(anotherAddressForTesting);
    }

    function testCannotAddOracleMemberAgain() public {
        cheats.prank(ORACLE_ADMIN_ADDRESS);
        cheats.expectRevert(OracleManager.OracleMemberExists.selector);
        oracleManager.addOracleMember(ORACLE_MEMBERS[0]);
    }

    function testRemoveOracleMember() public {
        cheats.prank(ORACLE_ADMIN_ADDRESS);
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
            "AccessControl: account 0x62d69f6867a0a084c6d313943dc22023bc263691 is missing role 0x323baab94aa45aaa3cc044271188889aad21b45e0260589722dc9ff769b4b1d8"
        );
        oracleManager.removeOracleMember(anotherAddressForTesting);
    }

    function testCannotRemoveOracleMemberIfNotPresent() public {
        cheats.prank(ORACLE_ADMIN_ADDRESS);
        cheats.expectRevert(OracleManager.OracleMemberNotFound.selector);
        oracleManager.removeOracleMember(0xf195179eEaE3c8CAB499b5181721e5C57e4769b2);
    }

    // -------------------------------------------------------------------------
    //  Address and auth management
    // -------------------------------------------------------------------------

    function testSetOracleAddress() public {
        cheats.prank(ORACLE_ADMIN_ADDRESS);
        cheats.expectEmit(false, false, false, true);
        emit OracleAddressChanged(anotherAddressForTesting);
        oracleManager.setOracleAddress(anotherAddressForTesting);
    }

    function testUnauthorizedSetOracleAddress() public {
        cheats.expectRevert(
            "AccessControl: account 0x62d69f6867a0a084c6d313943dc22023bc263691 is missing role 0x323baab94aa45aaa3cc044271188889aad21b45e0260589722dc9ff769b4b1d8"
        );
        oracleManager.setOracleAddress(anotherAddressForTesting);
    }

    // TODO: write and test changing ORACLE_ADMIN_ADDRESS

    // -------------------------------------------------------------------------
    //  TEMPORARY FUNCTION TEST - REMOVE WHEN FUNCTION IS REMOVED
    // -------------------------------------------------------------------------

    function testTemporaryFinalizeReport() public {
        cheats.prank(ORACLE_ADMIN_ADDRESS);
        oracleManager.setOracleAddress(address(oracle));

        Validator[] memory reportData = new Validator[](2);
        reportData[0] = ValidatorHelpers.packValidator(0, true, true, 100);
        reportData[1] = ValidatorHelpers.packValidator(1, true, true, 200);

        cheats.prank(ORACLE_MEMBERS[0]);
        cheats.expectEmit(false, false, false, true);
        emit OracleReportSent(epochId);
        oracleManager.temporaryFinalizeReport(epochId, reportData);
    }
}
