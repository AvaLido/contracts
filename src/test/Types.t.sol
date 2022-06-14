// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "forge-std/Test.sol";
import "./cheats.sol";
import "./helpers.sol";
import "../Types.sol";

contract TypesTest is DSTest, Helpers {
    function setUp() public {}

    function testHasUptime() public {
        uint24 withSet24 = 0 | (1 << 23);
        bool res = ValidatorHelpers.hasAcceptibleUptime(withSet24);
        assertTrue(res);
    }

    function testHasUptimeFalse() public {
        uint24 data = 1;
        bool res = ValidatorHelpers.hasAcceptibleUptime(data);
        assertTrue(!res);
    }

    function testHasTimeRemaining() public {
        uint24 data = 0;
        uint24 withSet23 = data | (1 << 22);
        bool res = ValidatorHelpers.hasTimeRemaining(withSet23);
        assertTrue(res);
    }

    function testHasTimeRemainingFalse() public {
        uint24 data = 0;
        bool res = ValidatorHelpers.hasTimeRemaining(data);
        assertTrue(!res);
    }

    function testHasTimeRemainingFalseWhenUptimeSet() public {
        uint24 data = 0 | (1 << 23); // set bit 8 (uptime bit)
        bool res = ValidatorHelpers.hasTimeRemaining(data);
        assertTrue(!res);
    }

    function testGetNodeIndexOne() public {
        uint24 one = 0 | (1 << 10); // Set first bit of index
        uint256 res = ValidatorHelpers.getNodeIndex(one);
        assertEq(res, 1);
    }

    function testGetNodeIndexWithFuzzing(uint24 x) public {
        cheats.assume(x < 4096);
        uint24 data = x << 10;
        uint256 res = ValidatorHelpers.getNodeIndex(data);
        assertEq(res, x);
    }

    function testFreeSpace() public {
        uint24 data = 0;
        uint256 space = ValidatorHelpers.freeSpace(data);
        assertEq(space, 0);
    }
}
