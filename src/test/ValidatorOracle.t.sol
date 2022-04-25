// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/utils/Strings.sol";

import "ds-test/test.sol";
// import "ds-test/src/test.sol";
import "./console.sol";
import "./cheats.sol";
import "./helpers.sol";

import "../ValidatorOracle.sol";

contract ValidatorOracleTest is DSTest, Helpers {
    ValidatorOracle oracle;

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
