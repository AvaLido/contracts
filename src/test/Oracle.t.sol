// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./cheats.sol";
import "./helpers.sol";

import "../Oracle.sol";
import "../OracleManager.sol";

contract OracleTest is DSTest, Helpers {
    Oracle oracle;

    event EpochDurationChanged(uint256 epochDuration);
    event OracleManagerAddressChanged(address newOracleManagerAddress);
    event OracleReportReceived(uint256 epochId);

    address[] ORACLE_MEMBERS = [
        WHITELISTED_ORACLE_1,
        WHITELISTED_ORACLE_2,
        WHITELISTED_ORACLE_3,
        WHITELISTED_ORACLE_4,
        WHITELISTED_ORACLE_5
    ];
    address ORACLE_MANAGER_CONTRACT_ADDRESS = 0xaFf132430941797A06ae017Ab2E9c5e791D5DF2C;
    uint256 epochId = 100;
    uint256 epochDuration = 100;
    string fakeNodeId = VALIDATOR_1;
    string[] validators = [VALIDATOR_1, VALIDATOR_2];

    function setUp() public {
        Oracle _oracle = new Oracle();
        oracle = Oracle(proxyWrapped(address(_oracle), ROLE_PROXY_ADMIN));
        oracle.initialize(ORACLE_ADMIN_ADDRESS, ORACLE_MANAGER_CONTRACT_ADDRESS, epochDuration);
    }

    function testOracleConstructor() public {
        assertEq(oracle.oracleManagerContract(), ORACLE_MANAGER_CONTRACT_ADDRESS);
    }

    // -------------------------------------------------------------------------
    //  Report functionality
    // -------------------------------------------------------------------------

    function testReceiveFinalizedReport() public {
        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, true, true, 100);

        // Epoch id should be 0 to start
        assertEq(oracle.latestFinalizedEpochId(), 0);

        cheats.expectEmit(false, false, false, true);
        emit OracleReportReceived(epochId);

        cheats.prank(ORACLE_MANAGER_CONTRACT_ADDRESS);
        oracle.receiveFinalizedReport(epochId, reportData);

        // Epoch id should be 100 after report
        assertEq(oracle.latestFinalizedEpochId(), 100);

        Validator[] memory dataFromContract = oracle.getAllValidatorsByEpochId(epochId);
        assertEq(keccak256(abi.encode(reportData)), keccak256(abi.encode(dataFromContract)));
        assertEq(oracle.latestFinalizedEpochId(), epochId);
    }

    function testReceiveFinalizedReportAfterSkippedEpochs() public {
        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, true, true, 100);

        // First report, epoch id should be 100
        cheats.prank(ORACLE_MANAGER_CONTRACT_ADDRESS);
        oracle.receiveFinalizedReport(epochId, reportData);
        assertEq(oracle.latestFinalizedEpochId(), 100);

        // Second report for epoch id of 500 should be able to be accepted
        uint256 muchLaterEpochId = 500;
        cheats.prank(ORACLE_MANAGER_CONTRACT_ADDRESS);
        oracle.receiveFinalizedReport(muchLaterEpochId, reportData);

        Validator[] memory dataFromContract = oracle.getAllValidatorsByEpochId(muchLaterEpochId);
        assertEq(keccak256(abi.encode(reportData)), keccak256(abi.encode(dataFromContract)));
        assertEq(oracle.latestFinalizedEpochId(), muchLaterEpochId);
    }

    function testCannotReceiveFinalizedReportForEpochsNotMatchingDuration() public {
        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, true, true, 100);

        // First report, epoch id should be 100
        cheats.prank(ORACLE_MANAGER_CONTRACT_ADDRESS);
        oracle.receiveFinalizedReport(epochId, reportData);
        assertEq(oracle.latestFinalizedEpochId(), 100);

        // Second report for epoch id of 300, should still be accepted even though the next ought to be 200
        uint256 invalidEpochId = 150;
        cheats.startPrank(ORACLE_MANAGER_CONTRACT_ADDRESS);
        cheats.expectRevert(Oracle.InvalidReportingEpoch.selector);
        oracle.receiveFinalizedReport(invalidEpochId, reportData);
        cheats.stopPrank();
    }

    function testUnauthorizedReceiveFinalizedReport() public {
        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, true, true, 100);
        cheats.expectRevert(Oracle.OnlyOracleManagerContract.selector);
        oracle.receiveFinalizedReport(epochId, reportData);
    }

    function testCannotReceiveFinalizedReportTwice() public {
        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, true, true, 100);

        cheats.expectEmit(false, false, false, true);
        emit OracleReportReceived(epochId);

        cheats.prank(ORACLE_MANAGER_CONTRACT_ADDRESS);
        oracle.receiveFinalizedReport(epochId, reportData);

        // Should fail because epoch is already finalized
        cheats.startPrank(ORACLE_MANAGER_CONTRACT_ADDRESS);
        cheats.expectRevert(Oracle.EpochAlreadyFinalized.selector);
        oracle.receiveFinalizedReport(epochId, reportData);
        cheats.stopPrank();
    }

    function testOldReportDoesNotUpdateLatest() public {
        uint256 reportingEpochId = 200;
        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, true, true, 100);

        cheats.startPrank(ORACLE_MANAGER_CONTRACT_ADDRESS);
        oracle.receiveFinalizedReport(reportingEpochId, reportData);

        // Epoch id should be 200 after report
        assertEq(oracle.latestFinalizedEpochId(), 200);

        // Send an old report, expect revert
        cheats.expectRevert(Oracle.InvalidReportingEpoch.selector);
        oracle.receiveFinalizedReport(reportingEpochId - epochDuration, reportData);

        // Latest should still be original epoch
        assertEq(oracle.latestFinalizedEpochId(), reportingEpochId);
    }

    function testCurrentReportableEpoch() public {
        // Assume we deploy at block 1337 with an epoch duration of 100
        // Current reportable block should be 1300
        cheats.roll(1337);
        assertEq(oracle.currentReportableEpoch(), 1300);
    }

    // -------------------------------------------------------------------------
    //  Management
    // -------------------------------------------------------------------------

    function testChangeOracleManagerAddress() public {
        address newManagerAddress = 0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2;
        cheats.expectEmit(false, false, false, true);
        emit OracleManagerAddressChanged(newManagerAddress);

        cheats.prank(ORACLE_ADMIN_ADDRESS);
        oracle.setOracleManagerAddress(newManagerAddress);
    }

    function testUnauthorizedChangeOracleManagerAddress() public {
        address newManagerAddress = 0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2;
        cheats.expectRevert(
            "AccessControl: account 0x62d69f6867a0a084c6d313943dc22023bc263691 is missing role 0x34a4d1a1986ad857ac4bae77830874ee3b64b359bb6bdc3f73a14cff3bb32bf6"
        );
        oracle.setOracleManagerAddress(newManagerAddress);
    }

    function testChangeRoleOracleAdmin() public {
        // Assert correct role assignment from deploy
        assertTrue(oracle.hasRole(ROLE_ORACLE_ADMIN, ORACLE_ADMIN_ADDRESS));

        // User 2 has no roles.
        assertTrue(!oracle.hasRole(ROLE_ORACLE_ADMIN, USER2_ADDRESS));

        // User 2 doesn't have permission to grant roles, so this should revert.
        cheats.expectRevert(
            "AccessControl: account 0x220866b1a2219f40e72f5c628b65d54268ca3a9d is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        cheats.prank(USER2_ADDRESS);
        oracle.grantRole(ROLE_ORACLE_ADMIN, USER2_ADDRESS);

        // But the contract deployer does have permission.
        cheats.prank(DEPLOYER_ADDRESS);
        oracle.grantRole(ROLE_ORACLE_ADMIN, USER2_ADDRESS);

        // User 2 now has a role 🎉
        assertTrue(oracle.hasRole(ROLE_ORACLE_ADMIN, USER2_ADDRESS));
    }

    function testSetNodeIDList() public {
        assertEq(oracle.validatorCount(), 0);

        cheats.prank(ORACLE_ADMIN_ADDRESS);
        oracle.setNodeIDList(validators);

        assertEq(oracle.validatorCount(), 2);
        assertEq(oracle.nodeIdByValidatorIndex(0), validators[0]);
    }

    function testChangeEpochDuration() public {
        uint256 newEpochDuration = 500;
        cheats.expectEmit(false, false, false, true);
        emit EpochDurationChanged(newEpochDuration);

        cheats.prank(ORACLE_ADMIN_ADDRESS);
        oracle.setEpochDuration(newEpochDuration);
    }

    function testUnauthorizedChangeEpochDuration() public {
        uint256 newEpochDuration = 500;
        cheats.expectRevert(
            "AccessControl: account 0x62d69f6867a0a084c6d313943dc22023bc263691 is missing role 0x34a4d1a1986ad857ac4bae77830874ee3b64b359bb6bdc3f73a14cff3bb32bf6"
        );
        oracle.setEpochDuration(newEpochDuration);
    }

    function testChangeEpochDurationToZero() public {
        uint256 newEpochDuration = 0;
        cheats.startPrank(ORACLE_ADMIN_ADDRESS);
        cheats.expectRevert(Oracle.InvalidEpochDuration.selector);
        oracle.setEpochDuration(newEpochDuration);
        cheats.stopPrank();
    }
}
