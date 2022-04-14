// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "../stAVAX.sol";

contract TestToken is stAVAX {
    uint256 public totalPooled = 0;

    function _setTotalPooled(uint256 _totalPooled) public {
        totalPooled = _totalPooled;
    }

    function getTotalPooledAvax() public view override returns (uint256) {
        return totalPooled;
    }
}

contract stAVAXTest is DSTest {
    TestToken stavax;

    function setUp() public {
        stavax = new TestToken();
    }

    function testExample() public {
        assertTrue(true);
    }
}
