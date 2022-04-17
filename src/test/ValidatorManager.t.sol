// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

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

    function getAvailableValidatorsWithCapacity(uint256 amount) external view override returns (Validator[] memory) {
        return validators;
    }
}

contract ValidatorManagerTest is DSTest {
    event StakeEvent(uint256 amount);

    ValidatorManager manager;
    MockOracle oracle;

    function nodeId(uint8 num) public pure returns (string memory) {
        return string(abi.encodePacked("NodeID-00000000000000000000000000000000", num));
    }

    function nValidatorsWithInitialAndStake(
        uint256 n,
        uint256 stake,
        uint256 full
    ) public pure returns (Validator[] memory) {
        Validator[] memory result = new Validator[](n);
        for (uint256 i = 0; i < n; i++) {
            // TODO fix
            // result[i] = Validator(0, stake, full, nodeId(uint8(n)));
            result[i] = Validator(0, stake, full, "NodeID-000000000000000000000000000000000");
        }
        return result;
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
        assertEq(keccak256(bytes(vals[0])), keccak256(bytes("NodeID-000000000000000000000000000000000")));

        assertEq(amounts.length, 1);
        assertEq(amounts[0], 50 ether);

        assertEq(remaining, 0);
    }
}
