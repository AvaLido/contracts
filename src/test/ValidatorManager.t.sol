// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/utils/Strings.sol";

import "ds-test/test.sol";
// import "ds-test/src/test.sol";
import "./console.sol";
import "./cheats.sol";

import "../interfaces/IValidatorOracle.sol";
import "../ValidatorManager.sol";

address constant ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;

contract MockOracle is BaseValidatorOracle {
    Validator[] public validators;

    function _setValidators(Validator[] memory vals) public {
        delete validators;
        for (uint256 i = 0; i < vals.length; i++) {
            validators.push(vals[i]);
        }
    }

    function getAvailableValidators() external view override returns (Validator[] memory) {
        return validators;
    }

    function getAvailableValidatorsWithCapacity(uint256) external view override returns (Validator[] memory) {
        return validators;
    }
}

contract ValidatorManagerTest is DSTest {
    event StakeEvent(uint256 amount);

    ValidatorManager manager;
    MockOracle oracle;

    // TODO: Some left-padding or similar to match real-world node IDs would be nice.
    function nodeId(uint256 num) public pure returns (string memory) {
        return string(abi.encodePacked("NodeID-", Strings.toString(num)));
    }

    function nValidatorsWithInitialAndStake(
        uint256 n,
        uint256 stake,
        uint256 full
    ) public pure returns (Validator[] memory) {
        Validator[] memory result = new Validator[](n);
        for (uint256 i = 0; i < n; i++) {
            result[i] = Validator(0, stake, full, nodeId(i));
        }
        return result;
    }

    function mixOfBigAndSmallValidators() public pure returns (Validator[] memory) {
        Validator[] memory smallValidators = nValidatorsWithInitialAndStake(7, 0.1 ether, 0);
        Validator[] memory bigValidators = nValidatorsWithInitialAndStake(7, 100 ether, 0);

        Validator[] memory validators = new Validator[](smallValidators.length + bigValidators.length);

        for (uint256 i = 0; i < smallValidators.length; i++) {
            validators[i] = smallValidators[i];
        }
        for (uint256 i = 0; i < bigValidators.length; i++) {
            validators[smallValidators.length + i] = bigValidators[i];
        }

        return validators;
    }

    function setUp() public {
        oracle = new MockOracle();
        manager = new ValidatorManager(address(oracle));
    }

    function testSelectZero() public {
        (string[] memory vals, uint256[] memory amounts, uint256 remaining) = manager.selectValidatorsForStake(0);
        assertEq(vals.length, 0);
        assertEq(amounts.length, 0);
        assertEq(remaining, 0);
    }

    function testSelectZeroCapacity() public {
        oracle._setValidators(new Validator[](0)); // nothing with capacity

        (string[] memory vals, uint256[] memory amounts, uint256 remaining) = manager.selectValidatorsForStake(50);
        assertEq(vals.length, 0);
        assertEq(amounts.length, 0);
        assertEq(remaining, 50);
    }

    function testSelectUnderThreshold() public {
        // one validator with lots of capacity
        oracle._setValidators(nValidatorsWithInitialAndStake(1, 500 ether, 0));

        (string[] memory vals, uint256[] memory amounts, uint256 remaining) = manager.selectValidatorsForStake(
            50 ether
        );
        assertEq(vals.length, 1);
        assertEq(keccak256(bytes(vals[0])), keccak256(bytes("NodeID-0")));

        assertEq(amounts.length, 1);
        assertEq(amounts[0], 50 ether);

        assertEq(remaining, 0);
    }

    function testSelectManyValidatorsUnderThreshold() public {
        // many validators with lots of capacity
        oracle._setValidators(nValidatorsWithInitialAndStake(1000, 500 ether, 0));

        (string[] memory vals, uint256[] memory amounts, uint256 remaining) = manager.selectValidatorsForStake(
            50 ether
        );
        assertEq(vals.length, 1);

        // Note: `manager.selectValidatorsForStake` selects a node to delegate to pseudo-randomly (via hashing).
        // If the selection algorithm changes, this unit test will fail as another node will have been selected.
        assertEq(keccak256(bytes(vals[0])), keccak256(bytes("NodeID-947")));

        assertEq(amounts.length, 1);
        assertEq(amounts[0], 50 ether);

        assertEq(remaining, 0);
    }

    function testSelectManyValidatorsOverThreshold() public {
        // many validators with limited of capacity
        oracle._setValidators(nValidatorsWithInitialAndStake(1000, 5 ether, 0));

        (string[] memory vals, uint256[] memory amounts, uint256 remaining) = manager.selectValidatorsForStake(
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
    }

    function testSelectManyValidatorsWithRemainder() public {
        // Odd number of stake/validators to check remainder
        oracle._setValidators(nValidatorsWithInitialAndStake(7, 10 ether, 0));

        (string[] memory vals, uint256[] memory amounts, uint256 remaining) = manager.selectValidatorsForStake(
            500 ether
        );
        assertEq(vals.length, 7);
        assertEq(keccak256(bytes(vals[6])), keccak256(bytes("NodeID-6")));

        assertEq(amounts.length, 7);
        assertEq(amounts[0], 40 ether);

        assertEq(remaining, 220 ether);
    }

    function testSelectManyValidatorsWithHighRemainder() public {
        // request of stake much higher than remaining capacity
        oracle._setValidators(nValidatorsWithInitialAndStake(10, 0.1 ether, 0));

        (, uint256[] memory amounts, uint256 remaining) = manager.selectValidatorsForStake(1000 ether);

        assertEq(amounts[0], 0.4 ether);
        assertEq(remaining, 996 ether);
    }

    function testSelectVariableValidatorSizesUnderThreshold() public {
        // request of stake where 1/N will completely fill some validators but others have space
        oracle._setValidators(mixOfBigAndSmallValidators());

        (, uint256[] memory amounts, uint256 remaining) = manager.selectValidatorsForStake(1000 ether);

        assertEq(amounts[0], 0.4 ether);
        assertEq(remaining, 0);
    }

    function testSelectVariableValidatorSizesFull() public {
        // request where the chunk size is small and some validators are full so we have to loop through many times
        oracle._setValidators(mixOfBigAndSmallValidators());

        (, uint256[] memory amounts, uint256 remaining) = manager.selectValidatorsForStake(10000 ether);

        assertEq(amounts[0], 0.4 ether);

        uint256 expectedRemaining = 10000 ether - (7 * 4 * 100 ether) - (7 * 4 * 0.1 ether);
        assertEq(remaining, expectedRemaining);
    }
}
