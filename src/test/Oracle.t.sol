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

    address ORACLE_MANAGER_ADDRESS;
    uint256 epochId = 123456789;
    string testData = "yeet";
    string fakeNodeId = "NodeId-123";

    function setUp() public {
        oracle = new Oracle();
        oracleManager = new OracleManager();
        ORACLE_MANAGER_ADDRESS = address(oracleManager);
        oracle.initialize(ORACLE_MANAGER_ADDRESS);
    }

    function testInitializeOracle() public {
        assertEq(oracle.ORACLE_MANAGER_CONTRACT(), ORACLE_MANAGER_ADDRESS);
    }

    // -------------------------------------------------------------------------
    //  Report functionality
    // -------------------------------------------------------------------------

    function testReceiveFinalizedReport() public {
        bytes32 hashedData = keccak256(abi.encode(testData));
        cheats.prank(ORACLE_MANAGER_ADDRESS);
        oracle.receiveFinalizedReport(epochId, hashedData);
        console.log("Data sent, now to read");
        bytes32 hashedDataFromContract = oracle.getValidatorDataByEpochId(epochId, fakeNodeId);
        assertEq(hashedData, hashedDataFromContract);
    }

    // -------------------------------------------------------------------------
    //  Auth
    // -------------------------------------------------------------------------

    function testUnauthorizedReceiveFinalizedReport() public {
        bytes32 hashedData = keccak256(abi.encode(testData));
        cheats.expectRevert(Oracle.OnlyOracleManager.selector);
        oracle.receiveFinalizedReport(epochId, hashedData);
    }
}
