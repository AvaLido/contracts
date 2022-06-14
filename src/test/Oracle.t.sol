// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

// import "ds-test/src/test.sol";
import "ds-test/test.sol";
import "./cheats.sol";
import "./helpers.sol";
import "../Oracle.sol";
import "../OracleManager.sol";

contract OracleTest is DSTest, Helpers {
    Oracle oracle;
    OracleManager oracleManager;

    event OracleManagerAddressChanged(address newOracleManagerAddress);
    event OracleReportReceived(uint256 epochId);
    // event RoleOracleManagerChanged(address newRoleOracleManager);

    string[] WHITELISTED_VALIDATORS = [WHITELISTED_VALIDATOR_1, WHITELISTED_VALIDATOR_2, WHITELISTED_VALIDATOR_3];
    address[] ORACLE_MEMBERS = [
        WHITELISTED_ORACLE_1,
        WHITELISTED_ORACLE_2,
        WHITELISTED_ORACLE_3,
        WHITELISTED_ORACLE_4,
        WHITELISTED_ORACLE_5
    ];
    address ORACLE_MANAGER_ADDRESS;
    uint256 epochId = 123456789;
    string fakeNodeId = WHITELISTED_VALIDATORS[0];

    function setUp() public {
        oracleManager = new OracleManager(ROLE_ORACLE_MANAGER, WHITELISTED_VALIDATORS, ORACLE_MEMBERS);
        ORACLE_MANAGER_ADDRESS = address(oracleManager);
        oracle = new Oracle(ROLE_ORACLE_MANAGER, ORACLE_MANAGER_ADDRESS);
        cheats.prank(ROLE_ORACLE_MANAGER);
        oracleManager.setOracleAddress(address(oracle));
    }

    function testOracleConstructor() public {
        assertEq(oracle.ORACLE_MANAGER_CONTRACT(), ORACLE_MANAGER_ADDRESS);
    }

    // -------------------------------------------------------------------------
    //  Report functionality
    // -------------------------------------------------------------------------

    function testReceiveFinalizedReport() public {
        cheats.prank(ORACLE_MANAGER_ADDRESS);
        Validator[] memory reportData = new Validator[](1);
        reportData[0].nodeId = fakeNodeId;

        cheats.expectEmit(false, false, false, true);
        emit OracleReportReceived(epochId);
        oracle.receiveFinalizedReport(epochId, reportData);

        Validator[] memory dataFromContract = oracle.getAllValidatorsByEpochId(epochId);
        assertEq(keccak256(abi.encode(reportData)), keccak256(abi.encode(dataFromContract)));
        assertEq(oracle.latestEpochId(), epochId);
    }

    function testUnauthorizedReceiveFinalizedReport() public {
        cheats.expectRevert(Oracle.OnlyOracleManager.selector);
        Validator[] memory reportData = new Validator[](1);
        reportData[0].nodeId = fakeNodeId;
        oracle.receiveFinalizedReport(epochId, reportData);
    }

    function testOldReportDoesNotUpdateLatest() public {
        Validator[] memory reportData = new Validator[](1);
        reportData[0].nodeId = fakeNodeId;

        cheats.startPrank(ORACLE_MANAGER_ADDRESS);
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
        cheats.prank(ROLE_ORACLE_MANAGER);
        cheats.expectEmit(false, false, false, true);
        emit OracleManagerAddressChanged(newManagerAddress);
        oracle.changeOracleManagerAddress(newManagerAddress);
    }

    function testUnauthorizedChangeOracleManagerAddress() public {
        address newManagerAddress = 0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2;
        cheats.expectRevert(
            "AccessControl: account 0xb4c79dab8f259c7aee6e5b2aa729821864227e84 is missing role 0x323baab94aa45aaa3cc044271188889aad21b45e0260589722dc9ff769b4b1d8"
        );
        oracle.changeOracleManagerAddress(newManagerAddress);
    }

    // TODO: write and test changing ROLE_ORACLE_MANAGER
}
