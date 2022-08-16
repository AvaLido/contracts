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
    uint256 epochId = 123456789;
    string fakeNodeId = VALIDATOR_1;
    string[] validators = [VALIDATOR_1, VALIDATOR_2];

    function setUp() public {
        Oracle _oracle = new Oracle();
        oracle = Oracle(proxyWrapped(address(_oracle), ROLE_PROXY_ADMIN));
        oracle.initialize(ORACLE_ADMIN_ADDRESS, ORACLE_MANAGER_CONTRACT_ADDRESS);
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

        cheats.expectEmit(false, false, false, true);
        emit OracleReportReceived(epochId);

        cheats.prank(ORACLE_MANAGER_CONTRACT_ADDRESS);
        oracle.receiveFinalizedReport(epochId, reportData);

        Validator[] memory dataFromContract = oracle.getAllValidatorsByEpochId(epochId);
        assertEq(keccak256(abi.encode(reportData)), keccak256(abi.encode(dataFromContract)));
        assertEq(oracle.latestEpochId(), epochId);
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
        Validator[] memory reportData = new Validator[](1);
        reportData[0] = ValidatorHelpers.packValidator(0, true, true, 100);

        cheats.startPrank(ORACLE_MANAGER_CONTRACT_ADDRESS);
        oracle.receiveFinalizedReport(epochId, reportData);

        // Send an old report
        oracle.receiveFinalizedReport(epochId - 1, reportData);

        // Latest should still be original epoch
        assertEq(oracle.latestEpochId(), epochId);
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

    // TODO: write and test changing ROLE_ORACLE_ADMIN

    // TODO: Test setting node id list

    function testSetNodeIDList() public {
        assertEq(oracle.validatorCount(), 0);

        cheats.prank(ORACLE_ADMIN_ADDRESS);
        oracle.setNodeIDList(validators);

        assertEq(oracle.validatorCount(), 2);
        assertEq(oracle.nodeIdByValidatorIndex(0), validators[0]);
    }
}
