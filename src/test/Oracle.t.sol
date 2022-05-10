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
    string testData = "yeet";
    string fakeNodeId = whitelistedValidators[0];

    function setUp() public {
        oracleManager = new OracleManager(roleOracleManager, whitelistedValidators, oracleMembers);
        ORACLE_MANAGER_ADDRESS = address(oracleManager);
        oracle = new Oracle(ORACLE_MANAGER_ADDRESS);
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
        cheats.prank(ORACLE_MANAGER_ADDRESS);
        oracle.receiveFinalizedReport(epochId, testData);
        string memory dataFromContract = oracle.getValidatorDataByEpochId(epochId, fakeNodeId);
        assertEq(testData, dataFromContract);
    }

    // -------------------------------------------------------------------------
    //  Auth
    // -------------------------------------------------------------------------

    function testUnauthorizedReceiveFinalizedReport() public {
        cheats.expectRevert(Oracle.OnlyOracleManager.selector);
        oracle.receiveFinalizedReport(epochId, testData);
    }
}
