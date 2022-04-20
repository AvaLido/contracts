// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/utils/Strings.sol";

import "ds-test/test.sol";
// import "ds-test/src/test.sol";
import "./console.sol";
import "./cheats.sol";

import "../ValidatorOracle.sol";

contract ValidatorOracleTest is DSTest {
    ValidatorOracle oracle;

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
        oracle = new ValidatorOracle();
    }

    function testGetByCapacityEmpty() public {
        assertEq(oracle.getAvailableValidatorsWithCapacity(1 ether).length, 0);
    }

    function testGetByCapacity() public {
        oracle._TEMP_setValidators(nValidatorsWithInitialAndStake(2, 1 ether, 0));

        assertEq(oracle.getAvailableValidatorsWithCapacity(1 ether).length, 2); // Smaller
        assertEq(oracle.getAvailableValidatorsWithCapacity(4 ether).length, 2); // Exact
        assertEq(oracle.getAvailableValidatorsWithCapacity(10 ether).length, 0); // Too big
    }
}
