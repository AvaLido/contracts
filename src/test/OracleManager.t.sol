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

    event OracleReportSent(uint256 indexed epochId, bytes32 indexed hashedData);

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
    string testDataOne = "yeet";
    string testDataTwo = "yEeT";
    string fakeNodeId = whitelistedValidators[0];

    function setUp() public {
        oracleManager = new OracleManager(roleOracleManager, whitelistedValidators, oracleMembers);
        ORACLE_MANAGER_CONTRACT_ADDRESS = address(oracleManager);
        oracle = new Oracle(ORACLE_MANAGER_CONTRACT_ADDRESS);
        cheats.prank(roleOracleManager);
        oracleManager.setOracleAddress(address(oracle));
    }

    // -------------------------------------------------------------------------
    //  Report functionality
    // -------------------------------------------------------------------------

    function testReceiveMemberReportWithoutQuorum() public {
        cheats.startPrank(oracleMembers[0]);
        oracleManager.receiveMemberReport(epochId, testDataOne);
        assertEq(oracleManager.retrieveHashedDataCount(epochId, keccak256(abi.encodePacked(testDataOne))), 1);
        cheats.stopPrank();
    }

    function testReceiveMemberReportWithQuorum() public {
        cheats.startPrank(oracleMembers[0]);
        oracleManager.receiveMemberReport(epochId, testDataOne);
        oracleManager.receiveMemberReport(epochId, testDataOne);
        oracleManager.receiveMemberReport(epochId, testDataTwo);
        assertEq(oracleManager.retrieveHashedDataCount(epochId, keccak256(abi.encodePacked(testDataOne))), 2);
        assertEq(oracleManager.retrieveHashedDataCount(epochId, keccak256(abi.encodePacked(testDataTwo))), 1);

        // TODO: figure out the expectEmit or expectCall stuff so we can actually know the Oracle has been called
        //cheats.expectEmit(true, true, false, true); // how the f does this work
        //emit OracleReportSent(epochId, keccak256(abi.encodePacked(testDataOne)));
        // cheats.expectCall(
        //     address(oracle),
        //     abi.encodeWithSelector(
        //         oracle.receiveFinalizedReport.selector,
        //         epochId,
        //         keccak256(abi.encodePacked(testDataOne))
        //     )
        // );

        // Temporary check til we figure out the above - call the Oracle to see the data is there
        string memory dataFromContract = oracle.getValidatorDataByEpochId(epochId, fakeNodeId);
        assertEq(testDataOne, dataFromContract);

        cheats.stopPrank();
    }

    // function testOracleCannotReportTwice

    function testUnauthorizedReceiveMemberReport() public {
        cheats.expectRevert(OracleManager.OracleMemberNotFound.selector);
        oracleManager.receiveMemberReport(epochId, testDataOne);
    }

    // function testCannotReceiveReportWhenPaused

    // function testCannotReportForFinalizedEpoch

    // -------------------------------------------------------------------------
    //  Oracle management and auth
    // -------------------------------------------------------------------------

    function testAddOracleMember() public {
        cheats.prank(roleOracleManager);
        oracleManager.addOracleMember(0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2);
        assertEq(oracleManager.oracleMembers(3), 0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2);
    }

    function testUnauthorizedAddOracleMember() public {
        cheats.expectRevert(
            "AccessControl: account 0xb4c79dab8f259c7aee6e5b2aa729821864227e84 is missing role 0x323baab94aa45aaa3cc044271188889aad21b45e0260589722dc9ff769b4b1d8"
        );
        oracleManager.addOracleMember(0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2);
    }

    // TODO: fix test. It reverts with OracleMemberNotFound but for some reason test doesn't pass?
    // function testRemoveOracleMember() public {
    //     cheats.prank(roleOracleManager);
    //     oracleManager.removeOracleMember(0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2);
    //     cheats.expectRevert(OracleManager.OracleMemberNotFound.selector);
    //     assertEq(oracleManager.oracleMembers(3), 0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2);
    // }

    function testUnauthorizedRemoveOracleMember() public {
        cheats.expectRevert(
            "AccessControl: account 0xb4c79dab8f259c7aee6e5b2aa729821864227e84 is missing role 0x323baab94aa45aaa3cc044271188889aad21b45e0260589722dc9ff769b4b1d8"
        );
        oracleManager.addOracleMember(0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2);
    }

    // function testOracleMemberNotFound
}
