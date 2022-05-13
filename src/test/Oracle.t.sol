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
        ValidatorData[] memory reportData = new ValidatorData[](1);
        reportData[0].nodeId = fakeNodeId;

        cheats.expectEmit(false, false, false, true);
        emit OracleReportReceived(epochId);
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

    // -------------------------------------------------------------------------
    //  Tests from ValidatorOracle.t.sol to reimplement
    // -------------------------------------------------------------------------

    // function testGetByCapacityEmpty() public {
    //     assertEq(oracle.getAvailableValidatorsWithCapacity(1 ether).length, 0);
    // }

    // function testGetByCapacity() public {
    //     oracle._TEMP_setValidators(nValidatorsWithInitialAndStake(2, 1 ether, 0, timeFromNow(30 days)));

    //     assertEq(oracle.getAvailableValidatorsWithCapacity(1 ether).length, 2); // Smaller
    //     assertEq(oracle.getAvailableValidatorsWithCapacity(4 ether).length, 2); // Exact
    //     assertEq(oracle.getAvailableValidatorsWithCapacity(10 ether).length, 0); // Too big
    // }

    // function testGetByCapacityWithinEndTime() public {
    //     oracle._TEMP_setValidators(nValidatorsWithInitialAndStake(2, 1 ether, 0, timeFromNow(10 days)));

    //     assertEq(oracle.getAvailableValidatorsWithCapacity(1 ether).length, 0);
    // }

    // -------------------------------------------------------------------------
    //  Tests from ValidatorManager.t.sol to reimplement
    // -------------------------------------------------------------------------

    // function testSelectZero() public {
    //     (string[] memory vals, uint256[] memory amounts, uint256 remaining) = manager.selectValidatorsForStake(0);
    //     assertEq(vals.length, 0);
    //     assertEq(amounts.length, 0);
    //     assertEq(remaining, 0);
    // }

    // function testSelectZeroCapacity() public {
    //     oracle._setValidators(new Validator[](0)); // nothing with capacity

    //     (string[] memory vals, uint256[] memory amounts, uint256 remaining) = manager.selectValidatorsForStake(50);
    //     assertEq(vals.length, 0);
    //     assertEq(amounts.length, 0);
    //     assertEq(remaining, 50);
    // }

    // function testSelectUnderThreshold() public {
    //     // one validator with lots of capacity
    //     oracle._setValidators(nValidatorsWithInitialAndStake(1, 500 ether, 0, timeFromNow(30 days)));

    //     (string[] memory vals, uint256[] memory amounts, uint256 remaining) = manager.selectValidatorsForStake(
    //         50 ether
    //     );
    //     assertEq(vals.length, 1);
    //     assertEq(keccak256(bytes(vals[0])), keccak256(bytes("NodeID-0")));

    //     assertEq(amounts.length, 1);
    //     assertEq(amounts[0], 50 ether);

    //     assertEq(remaining, 0);
    // }

    // // // TODO: figure out why this is failing on Github actions but not locally
    // // function testSelectManyValidatorsUnderThreshold() public {
    // //     // many validators with lots of capacity
    // //     oracle._setValidators(nValidatorsWithInitialAndStake(1000, 500 ether, 0, timeFromNow(30 days)));

    // //     (string[] memory vals, uint256[] memory amounts, uint256 remaining) = manager.selectValidatorsForStake(
    // //         50 ether
    // //     );
    // //     assertEq(vals.length, 1);

    // //     // Note: `manager.selectValidatorsForStake` selects a node to delegate to pseudo-randomly (via hashing).
    // //     // If the selection algorithm changes, this unit test will fail as another node will have been selected.
    // //     assertEq(keccak256(bytes(vals[0])), keccak256(bytes("NodeID-947")));

    // //     assertEq(amounts.length, 1);
    // //     assertEq(amounts[0], 50 ether);

    // //     assertEq(remaining, 0);
    // // }

    // function testSelectManyValidatorsOverThreshold() public {
    //     // many validators with limited of capacity
    //     oracle._setValidators(nValidatorsWithInitialAndStake(1000, 5 ether, 0, timeFromNow(30 days)));

    //     (string[] memory vals, uint256[] memory amounts, uint256 remaining) = manager.selectValidatorsForStake(
    //         500 ether
    //     );
    //     assertEq(vals.length, 1000);
    //     assertEq(keccak256(bytes(vals[1])), keccak256(bytes("NodeID-1")));
    //     assertEq(keccak256(bytes(vals[69])), keccak256(bytes("NodeID-69")));
    //     assertEq(keccak256(bytes(vals[420])), keccak256(bytes("NodeID-420")));

    //     assertEq(amounts.length, 1000);
    //     assertEq(amounts[0], 0.5 ether);
    //     assertEq(amounts[111], 0.5 ether);
    //     assertEq(amounts[222], 0.5 ether);
    //     assertEq(amounts[444], 0.5 ether);
    //     assertEq(amounts[888], 0.5 ether);

    //     assertEq(remaining, 0);
    // }

    // function testSelectManyValidatorsWithRemainder() public {
    //     // Odd number of stake/validators to check remainder
    //     oracle._setValidators(nValidatorsWithInitialAndStake(7, 10 ether, 0, timeFromNow(30 days)));

    //     (string[] memory vals, uint256[] memory amounts, uint256 remaining) = manager.selectValidatorsForStake(
    //         500 ether
    //     );
    //     assertEq(vals.length, 7);
    //     assertEq(keccak256(bytes(vals[6])), keccak256(bytes("NodeID-6")));

    //     assertEq(amounts.length, 7);
    //     assertEq(amounts[0], 40 ether);

    //     assertEq(remaining, 220 ether);
    // }

    // function testSelectManyValidatorsWithHighRemainder() public {
    //     // request of stake much higher than remaining capacity
    //     oracle._setValidators(nValidatorsWithInitialAndStake(10, 0.1 ether, 0, timeFromNow(30 days)));

    //     (, uint256[] memory amounts, uint256 remaining) = manager.selectValidatorsForStake(1000 ether);

    //     assertEq(amounts[0], 0.4 ether);
    //     assertEq(remaining, 996 ether);
    // }

    // function testSelectVariableValidatorSizesUnderThreshold() public {
    //     // request of stake where 1/N will completely fill some validators but others have space
    //     oracle._setValidators(mixOfBigAndSmallValidators());

    //     (, uint256[] memory amounts, uint256 remaining) = manager.selectValidatorsForStake(1000 ether);

    //     assertEq(amounts[0], 0.4 ether);
    //     assertEq(remaining, 0);
    // }

    // function testSelectVariableValidatorSizesFull() public {
    //     // request where the chunk size is small and some validators are full so we have to loop through many times
    //     oracle._setValidators(mixOfBigAndSmallValidators());

    //     (, uint256[] memory amounts, uint256 remaining) = manager.selectValidatorsForStake(10000 ether);

    //     assertEq(amounts[0], 0.4 ether);

    //     uint256 expectedRemaining = 10000 ether - (7 * 4 * 100 ether) - (7 * 4 * 0.1 ether);
    //     assertEq(remaining, expectedRemaining);
    // }
}
