// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

// import "ds-test/src/test.sol";
import "ds-test/test.sol";
import "./cheats.sol";
import "./helpers.sol";
import "./console.sol";
import "../Oracle.sol";
import "../OracleManager.sol";

contract OracleTest is DSTest, Helpers {
    Oracle oracle;
    OracleManager oracleManager;

    event OracleManagerAddressChanged(address newOracleManagerAddress);
    event OracleReportReceived(uint256 epochId);
    // event RoleOracleManagerChanged(address newRoleOracleManager);

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
    address ORACLE_MANAGER_ADDRESS;
    uint256 epochId = 123456789;
    string fakeNodeId = whitelistedValidators[0];

    function setUp() public {
        oracleManager = new OracleManager(roleOracleManager, whitelistedValidators, oracleMembers);
        ORACLE_MANAGER_ADDRESS = address(oracleManager);
        oracle = new Oracle(roleOracleManager, ORACLE_MANAGER_ADDRESS);
        cheats.prank(roleOracleManager);
        oracleManager.setOracleAddress(address(oracle));
    }

    function testOracleConstructor() public {
        assertEq(oracle.ORACLE_MANAGER_CONTRACT(), ORACLE_MANAGER_ADDRESS);
    }

    // -------------------------------------------------------------------------
    //  Report functionality
    // -------------------------------------------------------------------------

    function testReceiveFinalizedReport() public {
        cheats.expectEmit(false, false, false, true);
        emit OracleReportReceived(epochId);
        cheats.prank(ORACLE_MANAGER_ADDRESS);
        ValidatorData[] memory reportData = new ValidatorData[](1);
        reportData[0].nodeId = fakeNodeId;
        oracle.receiveFinalizedReport(epochId, reportData);
        ValidatorData[] memory dataFromContract = oracle.getAllValidatorDataByEpochId(epochId);
        assertEq(keccak256(abi.encode(reportData)), keccak256(abi.encode(dataFromContract)));
    }

    function testUnauthorizedReceiveFinalizedReport() public {
        cheats.expectRevert(Oracle.OnlyOracleManager.selector);
        ValidatorData[] memory reportData = new ValidatorData[](1);
        reportData[0].nodeId = fakeNodeId;
        oracle.receiveFinalizedReport(epochId, reportData);
    }

    // -------------------------------------------------------------------------
    //  Management
    // -------------------------------------------------------------------------

    function testChangeOracleManagerAddress() public {
        address newManagerAddress = 0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2;
        cheats.expectEmit(false, false, false, true);
        emit OracleManagerAddressChanged(newManagerAddress);
        cheats.prank(roleOracleManager);
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
