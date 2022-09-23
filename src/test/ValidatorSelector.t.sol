// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

import "./helpers.sol";
import "../stAVAX.sol";

import "../interfaces/IOracle.sol";

contract MockHelpers is Test {
    function timeFromNow(uint256 time) public view returns (uint64) {
        return uint64(block.timestamp + time);
    }

    function nValidatorsWithFreeSpace(uint256 n, uint256 freeSpace) public pure returns (Validator[] memory) {
        Validator[] memory result = new Validator[](n);
        for (uint256 i = 0; i < n; i++) {
            result[i] = ValidatorHelpers.packValidator(uint16(i), uint16(freeSpace / 100 ether));
        }
        return result;
    }

    function oracleDataMock(address oracle, Validator[] memory data) public {
        vm.mockCall(oracle, abi.encodeWithSelector(IOracle.getLatestValidators.selector), abi.encode(data));
    }

    function oracleIndexMock(
        address oracle,
        uint256 index,
        string memory nodeId
    ) public {
        vm.mockCall(oracle, abi.encodeWithSelector(IOracle.nodeIdByValidatorIndex.selector, index), abi.encode(nodeId));
    }

    function mixOfBigAndSmallValidators() public pure returns (Validator[] memory) {
        Validator[] memory smallValidators = nValidatorsWithFreeSpace(7, 500 ether);
        Validator[] memory bigValidators = nValidatorsWithFreeSpace(7, 100000 ether);

        Validator[] memory validators = new Validator[](smallValidators.length + bigValidators.length);

        for (uint256 i = 0; i < smallValidators.length; i++) {
            validators[i] = smallValidators[i];
        }
        for (uint256 i = 0; i < bigValidators.length; i++) {
            validators[smallValidators.length + i] = bigValidators[i];
        }

        return validators;
    }

    function mixOfSuitableAndUnsuitableValidators() public pure returns (Validator[] memory) {
        uint256 n = 5;
        uint256 freeSpace = 500;
        Validator[] memory unsuitableValidators = new Validator[](n);
        for (uint256 i = 0; i < n; i++) {
            unsuitableValidators[i] = ValidatorHelpers.packValidator(uint16(i), uint16(freeSpace / 100 ether));
        }
        Validator[] memory suitableValidators = nValidatorsWithFreeSpace(n, 100000 ether);

        Validator[] memory validators = new Validator[](unsuitableValidators.length + suitableValidators.length);

        for (uint256 i = 0; i < unsuitableValidators.length; i++) {
            validators[i] = unsuitableValidators[i];
        }
        for (uint256 i = 0; i < suitableValidators.length; i++) {
            validators[unsuitableValidators.length + i] = suitableValidators[i];
        }

        return validators;
    }
}

contract MockOracle is IOracle {
    function nodeId(uint256 num) public pure returns (string memory) {
        return string(abi.encodePacked("NodeID-", Strings.toString(num)));
    }

    function receiveFinalizedReport(uint256, Validator[] calldata) public pure {
        revert("Should not be called from ValidatorSelector");
    }

    function getLatestValidators() public pure returns (Validator[] memory) {
        revert("Should be mocked");
    }

    function validatorCount() external pure returns (uint256) {
        revert("Should be mocked");
    }

    function currentReportableEpoch() external pure returns (uint256) {
        revert("Should be mocked");
    }

    function isReportingEpochValid(uint256) external pure returns (bool) {
        revert("Should be mocked");
    }

    /**
     * @dev Replace this function to always return `Node-${N}` in tests.
     * For other cases, this should be mocked.
     */
    function nodeIdByValidatorIndex(uint256 index) public pure returns (string memory) {
        return nodeId(index);
    }
}

contract ValidatorSelectorTest is Test, MockHelpers, Helpers {
    ValidatorSelector selector;

    address oracleAddress;

    function setUp() public {
        IOracle oracle = IOracle(new MockOracle());
        oracleAddress = address(oracle);

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
        oracleDataMock(oracleAddress, nValidatorsWithFreeSpace(0, 0 ether));

        assertEq(selector.getAvailableValidatorsWithCapacity(1 ether).length, 0);
    }

    function testGetByCapacity() public {
        oracleDataMock(oracleAddress, nValidatorsWithFreeSpace(2, 1000 ether));

        assertEq(selector.getAvailableValidatorsWithCapacity(100 ether).length, 2); // Smaller
        assertEq(selector.getAvailableValidatorsWithCapacity(1000 ether).length, 2); // Exact
        assertEq(selector.getAvailableValidatorsWithCapacity(10000 ether).length, 0); // Too big
    }

    function testGetByCapacityRounding() public {
        oracleDataMock(oracleAddress, nValidatorsWithFreeSpace(1, 1234 ether));

        // Values are rounded down and stored as '100s of free avax'
        assertEq(selector.getAvailableValidatorsWithCapacity(1100 ether).length, 1); // Smaller
        assertEq(selector.getAvailableValidatorsWithCapacity(1234 ether).length, 0); // 0 because rounded
    }

    function testGetByCapacityWithinEndTime() public {
        oracleDataMock(oracleAddress, nValidatorsWithFreeSpace(2, 10 ether));
        assertEq(selector.getAvailableValidatorsWithCapacity(1 ether).length, 0);
    }

    function testGetAvailableValidatorsWithCapacityRegression() public {
        // This is a regression test to make sure we avoid the "index out of bounds" error
        oracleDataMock(oracleAddress, mixOfSuitableAndUnsuitableValidators());

        // Of 10 validators we should have 5 suitable
        assertEq(selector.getAvailableValidatorsWithCapacity(500 ether).length, 5);
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
        oracleDataMock(oracleAddress, nValidatorsWithFreeSpace(1, 0));

        (string[] memory vals, uint256[] memory amounts, uint256 remaining) = selector.selectValidatorsForStake(50);
        assertEq(vals.length, 0);
        assertEq(amounts.length, 0);
        assertEq(remaining, 50);
    }

    function testSelectUnderThreshold() public {
        // one validator with lots of capacity
        oracleDataMock(oracleAddress, nValidatorsWithFreeSpace(1, 2000 ether));

        (string[] memory vals, uint256[] memory amounts, uint256 remaining) = selector.selectValidatorsForStake(
            50 ether
        );
        assertEq(vals.length, 1);
        assertEq(keccak256(bytes(vals[0])), keccak256(bytes("NodeID-0")));

        assertEq(amounts.length, 1);
        assertEq(amounts[0], 50 ether);

        assertEq(remaining, 0);
    }

    function testSelectManyValidatorsOverThreshold() public {
        // many validators with limited of capacity
        oracleDataMock(oracleAddress, nValidatorsWithFreeSpace(1000, 500 ether));

        (string[] memory vals, uint256[] memory amounts, uint256 remaining) = selector.selectValidatorsForStake(
            500 ether
        );
        assertEq(vals.length, 1000);
        assertEq(amounts.length, 1000);

        // Should have 500 avax staked on one pseudo-random node.
        int256 chosenIndex = -1;
        for (uint256 i = 0; i < vals.length; i++) {
            if (amounts[i] > 0) {
                chosenIndex = int256(i);
            }
        }
        assertEq(
            keccak256(bytes(vals[uint256(chosenIndex)])),
            keccak256(bytes(string(abi.encodePacked("NodeID-", Strings.toString(uint256(chosenIndex))))))
        );

        assert(chosenIndex != -1);
        assertEq(remaining, 0);
        assertSumEq(amounts, 500 ether);
    }

    function testSelectManyValidatorsOverThresholdSmallCapacity() public {
        // many validators with loads of capacity.
        // Should get at most `maxChunkSize` on each until the request is filled.
        oracleDataMock(oracleAddress, nValidatorsWithFreeSpace(1000, 500 ether));

        (string[] memory vals, uint256[] memory amounts, uint256 remaining) = selector.selectValidatorsForStake(
            50000 ether
        );
        assertEq(vals.length, 1000);
        assertEq(amounts.length, 1000);

        // Should have 500 avax staked on one pseudo-random node.
        uint256 numAllocated = 0;
        for (uint256 i = 0; i < vals.length; i++) {
            if (amounts[i] > 0) {
                numAllocated++;
            }
        }

        // Should fill 500 on 100 nodes
        assertEq(numAllocated, 100);
        assertEq(remaining, 0);
        assertSumEq(amounts, 50000 ether);
    }

    function testSelectManyValidatorsOverThresholdLargeCapacity() public {
        // many validators with loads of capacity.
        // Should get at most `maxChunkSize` on each until the request is filled.
        oracleDataMock(oracleAddress, nValidatorsWithFreeSpace(1000, 50000 ether));

        (string[] memory vals, uint256[] memory amounts, uint256 remaining) = selector.selectValidatorsForStake(
            50000 ether
        );
        assertEq(vals.length, 1000);
        assertEq(amounts.length, 1000);

        uint256 numAllocated = 0;
        for (uint256 i = 0; i < vals.length; i++) {
            if (amounts[i] > 0) {
                numAllocated++;
            }
        }

        // Should fill 1000 (max) on 50 nodes
        assertEq(numAllocated, 50);
        assertEq(remaining, 0);
        assertSumEq(amounts, 50000 ether);
    }

    function testSelectManyValidatorsWithRemainder() public {
        // Odd number of stake/validators to check remainder
        oracleDataMock(oracleAddress, nValidatorsWithFreeSpace(7, 400 ether));

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
        oracleDataMock(oracleAddress, nValidatorsWithFreeSpace(10, 400 ether));

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
