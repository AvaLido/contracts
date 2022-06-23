// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./cheats.sol";
import "./helpers.sol";
import "../stAVAX.sol";

import "../interfaces/IOracle.sol";

contract MockHelpers {
    // TODO: Some left-padding or similar to match real-world node IDs would be nice.
    function nodeId(uint256 num) public pure returns (string memory) {
        return string(abi.encodePacked("NodeID-", Strings.toString(num)));
    }

    function timeFromNow(uint256 time) public view returns (uint64) {
        return uint64(block.timestamp + time);
    }

    function nValidatorsWithFreeSpace(
        uint256 n,
        uint64 endTime,
        uint256 freeSpace
    ) public pure returns (Validator[] memory) {
        Validator[] memory result = new Validator[](n);
        for (uint256 i = 0; i < n; i++) {
            result[i] = Validator(nodeId(i), endTime, freeSpace);
        }
        return result;
    }

    function oracleDataMock(address oracle, Validator[] memory data) public {
        cheats.mockCall(oracle, abi.encodeWithSelector(IOracle.getLatestValidator.selector), abi.encode(data));
    }

    function mixOfBigAndSmallValidators() public view returns (Validator[] memory) {
        Validator[] memory smallValidators = nValidatorsWithFreeSpace(7, timeFromNow(30 days), 500 ether);
        Validator[] memory bigValidators = nValidatorsWithFreeSpace(7, timeFromNow(30 days), 100000 ether);

        Validator[] memory validators = new Validator[](smallValidators.length + bigValidators.length);

        for (uint256 i = 0; i < smallValidators.length; i++) {
            validators[i] = smallValidators[i];
        }
        for (uint256 i = 0; i < bigValidators.length; i++) {
            validators[smallValidators.length + i] = bigValidators[i];
        }

        return validators;
    }
}

contract ValidatorSelectorTest is DSTest, MockHelpers, Helpers {
    ValidatorSelector selector;

    // Actual address irrelevant as function is mocked
    address oracleAddress = address(0x9000000000000000000000000000000000000000);

    function setUp() public {
        ValidatorSelector _selector = new ValidatorSelector();
        selector = ValidatorSelector(proxyWrapped(address(_selector), ROLE_PROXY_ADMIN));
        selector.initialize(oracleAddress);
    }

    function assertSumEq(uint256[] memory amounts, uint256 total) public {
        uint256 sum = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            sum += amounts[i];
        }
        assertEq(sum, total);
    }

    function testGetByCapacityEmpty() public {
        // Note: This has 0 validators.
        oracleDataMock(oracleAddress, nValidatorsWithFreeSpace(0, timeFromNow(30 days), 0 ether));

        assertEq(selector.getAvailableValidatorsWithCapacity(1 ether).length, 0);
    }

    function testGetByCapacity() public {
        oracleDataMock(oracleAddress, nValidatorsWithFreeSpace(2, timeFromNow(30 days), 4 ether));

        assertEq(selector.getAvailableValidatorsWithCapacity(1 ether).length, 2); // Smaller
        assertEq(selector.getAvailableValidatorsWithCapacity(4 ether).length, 2); // Exact
        assertEq(selector.getAvailableValidatorsWithCapacity(10 ether).length, 0); // Too big
    }

    function testGetByCapacityWithinEndTime() public {
        oracleDataMock(oracleAddress, nValidatorsWithFreeSpace(2, timeFromNow(10 days), 10 ether));
        assertEq(selector.getAvailableValidatorsWithCapacity(1 ether).length, 0);
    }

    function testSelectZero() public {
        (string[] memory vals, uint256[] memory amounts, uint256 remaining) = selector.selectValidatorsForStake(0);
        assertEq(vals.length, 0);
        assertEq(amounts.length, 0);
        assertEq(remaining, 0);
    }

    function testSelectNoValidators() public {
        oracleDataMock(oracleAddress, new Validator[](0));

        (string[] memory vals, uint256[] memory amounts, uint256 remaining) = selector.selectValidatorsForStake(50);
        assertEq(vals.length, 0);
        assertEq(amounts.length, 0);
        assertEq(remaining, 50);
    }

    function testSelectZeroCapacity() public {
        // 1 validator with no capacity
        oracleDataMock(oracleAddress, nValidatorsWithFreeSpace(1, timeFromNow(30 days), 0));

        (string[] memory vals, uint256[] memory amounts, uint256 remaining) = selector.selectValidatorsForStake(50);
        assertEq(vals.length, 0);
        assertEq(amounts.length, 0);
        assertEq(remaining, 50);
    }

    function testSelectUnderThreshold() public {
        // one validator with lots of capacity
        oracleDataMock(oracleAddress, nValidatorsWithFreeSpace(1, timeFromNow(30 days), 2000 ether));

        (string[] memory vals, uint256[] memory amounts, uint256 remaining) = selector.selectValidatorsForStake(
            50 ether
        );
        assertEq(vals.length, 1);
        assertEq(keccak256(bytes(vals[0])), keccak256(bytes("NodeID-0")));

        assertEq(amounts.length, 1);
        assertEq(amounts[0], 50 ether);

        assertEq(remaining, 0);
    }

    // // TODO: figure out why this is failing on Github actions but not locally
    // function testSelectManyValidatorsUnderThreshold() public {
    //     // many validators with lots of capacity
    //     oracleDataMock(nValidatorsWithFreeSpace(1000, timeFromNow(30 days), 500 ether));

    //     (string[] memory vals, uint256[] memory amounts, uint256 remaining) = selector.selectValidatorsForStake(
    //         50 ether
    //     );
    //     assertEq(vals.length, 1);

    //     // Note: `selector.selectValidatorsForStake` selects a node to delegate to pseudo-randomly (via hashing).
    //     // If the selection algorithm changes, this unit test will fail as another node will have been selected.
    //     assertEq(keccak256(bytes(vals[0])), keccak256(bytes("NodeID-947")));

    //     assertEq(amounts.length, 1);
    //     assertEq(amounts[0], 50 ether);

    //     assertEq(remaining, 0);
    // }

    function testSelectManyValidatorsOverThreshold() public {
        // many validators with limited of capacity
        oracleDataMock(oracleAddress, nValidatorsWithFreeSpace(1000, timeFromNow(30 days), 500 ether));

        (string[] memory vals, uint256[] memory amounts, uint256 remaining) = selector.selectValidatorsForStake(
            500 ether
        );
        assertEq(vals.length, 1000);
        assertEq(keccak256(bytes(vals[1])), keccak256(bytes("NodeID-1")));
        assertEq(keccak256(bytes(vals[69])), keccak256(bytes("NodeID-69")));
        assertEq(keccak256(bytes(vals[420])), keccak256(bytes("NodeID-420")));

        assertEq(amounts.length, 1000);
        assertEq(amounts[0], 0.5 ether);
        assertEq(amounts[111], 0.5 ether);
        assertEq(amounts[222], 0.5 ether);
        assertEq(amounts[444], 0.5 ether);
        assertEq(amounts[888], 0.5 ether);

        assertEq(remaining, 0);
        assertSumEq(amounts, 500 ether);
    }

    function testSelectManyValidatorsWithRemainder() public {
        // Odd number of stake/validators to check remainder
        oracleDataMock(oracleAddress, nValidatorsWithFreeSpace(7, timeFromNow(30 days), 400 ether));

        (string[] memory vals, uint256[] memory amounts, uint256 remaining) = selector.selectValidatorsForStake(
            5000 ether
        );
        assertEq(vals.length, 7);
        assertEq(keccak256(bytes(vals[6])), keccak256(bytes("NodeID-6")));

        assertEq(amounts.length, 7);
        assertEq(amounts[0], 400 ether);

        assertEq(remaining, 2200 ether);
        assertSumEq(amounts, 2800 ether);
    }

    function testSelectManyValidatorsWithHighRemainder() public {
        // request of stake much higher than remaining capacity
        oracleDataMock(oracleAddress, nValidatorsWithFreeSpace(10, timeFromNow(30 days), 400 ether));

        (, uint256[] memory amounts, uint256 remaining) = selector.selectValidatorsForStake(10000 ether);

        assertEq(amounts[0], 400 ether);
        assertEq(remaining, 6000 ether);
        assertSumEq(amounts, 4000 ether);
    }

    function testSelectVariableValidatorSizesUnderThreshold() public {
        // request of stake where 1/N will completely fill some validators but others have space
        oracleDataMock(oracleAddress, mixOfBigAndSmallValidators());

        (, uint256[] memory amounts, uint256 remaining) = selector.selectValidatorsForStake(100000 ether);

        assertEq(amounts[0], 500 ether);
        assertSumEq(amounts, 100000 ether);
        assertEq(remaining, 0);
    }

    function testSelectVariableValidatorSizesFull() public {
        // request where the chunk size is small and some validators are full so we have to loop through many times
        oracleDataMock(oracleAddress, mixOfBigAndSmallValidators());

        (, uint256[] memory amounts, uint256 remaining) = selector.selectValidatorsForStake(1_000_000 ether);

        assertEq(amounts[0], 500 ether);

        // 703500 total capacity.
        assertSumEq(amounts, 703500 ether);
        uint256 expectedRemaining = 1_000_000 ether - (7 * 100000 ether) - (7 * 500 ether);
        assertEq(remaining, expectedRemaining);
    }
}
