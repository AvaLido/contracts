// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

// import "ds-test/src/test.sol";
import "ds-test/test.sol";
import "./cheats.sol";
import "./console.sol";
import "../stAVAX.sol";

address constant ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;
address constant USER1_ADDRESS = 0x0000000000000000000000000000000000000001;
address constant USER2_ADDRESS = 0x0000000000000000000000000000000000000002;

contract TestToken is stAVAX {
    uint256 public totalControlled = 0;

    function _setTotalControlled(uint256 _totalControlled) public {
        totalControlled = _totalControlled;
    }

    function protocolControlledAVAX() public view override returns (uint256) {
        return totalControlled;
    }

    function proxyMint(address recipient, uint256 amount) public {
        super.mint(recipient, amount);
    }

    function proxyBurn(address owner, uint256 amount) public {
        super.burn(owner, amount);
    }
}

contract stAVAXTest is DSTest {
    TestToken stavax;

    function setUp() public {
        stavax = new TestToken();
    }

    function testSharesSingleUser() public {
        stavax.proxyMint(USER1_ADDRESS, 100 ether);
        stavax._setTotalControlled(100 ether);

        assertEq(stavax.totalSupply(), 100 ether);
        assertEq(stavax.balanceOf(USER1_ADDRESS), 100 ether);
    }

    function testSharesSingleUserBurn() public {
        stavax.proxyMint(USER1_ADDRESS, 100 ether);
        stavax.proxyBurn(USER1_ADDRESS, 10 ether);
        stavax._setTotalControlled(90 ether);

        assertEq(stavax.totalSupply(), 90 ether);
        assertEq(stavax.balanceOf(USER1_ADDRESS), 90 ether);
    }

    function testSharesSingleUserNotEqual() public {
        stavax.proxyMint(USER1_ADDRESS, 100 ether);
        stavax._setTotalControlled(50 ether);

        assertEq(stavax.balanceOf(USER1_ADDRESS), 50 ether);
    }

    function testSharesMultipleUser() public {
        stavax.proxyMint(USER1_ADDRESS, 100 ether);
        stavax.proxyMint(USER2_ADDRESS, 100 ether);
        stavax._setTotalControlled(100 ether);

        assertEq(stavax.balanceOf(USER1_ADDRESS), 50 ether);
        assertEq(stavax.balanceOf(USER2_ADDRESS), 50 ether);
    }

    function testSharesMultipleUserBurn() public {
        stavax.proxyMint(USER1_ADDRESS, 100 ether);
        stavax.proxyMint(USER2_ADDRESS, 100 ether);
        stavax._setTotalControlled(100 ether);

        // Ater burn, USER1 has 60 AVAX remaining; total in protocol is now 160.
        stavax.proxyBurn(USER1_ADDRESS, 40 ether);

        assertEq(stavax.balanceOf(USER1_ADDRESS), (60 ether / 160) * 100);
        assertEq(stavax.balanceOf(USER2_ADDRESS), (100 ether / 160) * 100);
    }

    function testSharesMultipleUserNotEqual() public {
        stavax.proxyMint(USER1_ADDRESS, 2 ether);
        stavax.proxyMint(USER2_ADDRESS, 8 ether);
        stavax._setTotalControlled(50 ether);

        assertEq(stavax.balanceOf(USER1_ADDRESS), 10 ether);
        assertEq(stavax.balanceOf(USER2_ADDRESS), 40 ether);
    }

    function testSharesMultipleUserWithFuzzing(uint256 u1Amount, uint256 u2Amount) public {
        // AVAX total supply ~300m
        cheats.assume(u1Amount < 300_000_000 ether);
        cheats.assume(u2Amount < 300_000_000 ether);

        stavax.proxyMint(USER1_ADDRESS, u1Amount);
        stavax.proxyMint(USER2_ADDRESS, u2Amount);
        stavax._setTotalControlled(u1Amount + u2Amount);

        assertEq(stavax.balanceOf(USER1_ADDRESS), u1Amount);
        assertEq(stavax.balanceOf(USER2_ADDRESS), u2Amount);
    }

    function testSharesMultipleUserNotRound() public {
        stavax.proxyMint(USER1_ADDRESS, 2 ether);
        stavax.proxyMint(USER2_ADDRESS, 1 ether);
        stavax._setTotalControlled(100 ether);

        assertEq(stavax.balanceOf(USER1_ADDRESS), 66666666666666666666);
        assertEq(stavax.balanceOf(USER2_ADDRESS), 33333333333333333333);
    }

    function testTransferNoZero() public {
        stavax._setTotalControlled(10 ether);
        stavax.proxyMint(USER1_ADDRESS, 2 ether);

        cheats.prank(USER1_ADDRESS);
        cheats.expectRevert(stAVAX.CannotSendToZeroAddress.selector);
        stavax.transfer(ZERO_ADDRESS, 1 ether);

        // Original balance remains
        assertEq(stavax.balanceOf(USER1_ADDRESS), 10 ether);
    }

    function testTransferNoBalance() public {
        stavax._setTotalControlled(10 ether);
        stavax.proxyMint(USER1_ADDRESS, 2 ether);

        cheats.prank(USER1_ADDRESS);
        cheats.expectRevert(stAVAX.InsufficientSTAVAXBalance.selector);
        stavax.transfer(USER2_ADDRESS, 3 ether);

        // Original balance remains
        assertEq(stavax.balanceOf(USER1_ADDRESS), 10 ether);
    }

    function testTransfer() public {
        stavax._setTotalControlled(10 ether);
        stavax.proxyMint(USER1_ADDRESS, 2 ether);

        cheats.prank(USER1_ADDRESS);
        bool res = stavax.transfer(USER2_ADDRESS, 1 ether);
        assertTrue(res);

        // Equal share of the 10 eth in the protocol.
        assertEq(stavax.balanceOf(USER1_ADDRESS), 5 ether);
        assertEq(stavax.balanceOf(USER2_ADDRESS), 5 ether);
    }
}
