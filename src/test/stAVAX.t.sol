// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

// import "ds-test/src/test.sol";
import "ds-test/test.sol";
import "./cheats.sol";
import "./helpers.sol";
import "./console.sol";
import "../stAVAX.sol";

contract TestToken is stAVAX {
    uint256 public totalControlled = 0;

    function _setTotalControlled(uint256 _totalControlled) public {
        totalControlled = _totalControlled;
    }

    function protocolControlledAVAX() public view override returns (uint256) {
        return totalControlled;
    }

    function deposit(address sender) public payable {
        uint256 amount = msg.value;
        totalControlled += amount;
        Shares256 shares = _getDepositSharesByAmount(amount);
        if (Shares256.unwrap(shares) == 0) {
            // `totalShares` is 0: this is the first ever deposit. Assume that shares correspond to AVAX 1-to-1.
            shares = Shares256.wrap(amount);
        }
        _mintShares(sender, shares);
    }

    function withdraw(address owner, uint256 amount) public {
        Shares256 shares = super.getSharesByAmount(amount);
        _burnShares(owner, shares);
        totalControlled -= amount;
    }
}

contract stAVAXTest is DSTest, Helpers {
    TestToken stavax;

    function setUp() public {
        stavax = new TestToken();
    }

    function testSharesSingleUser() public {
        stavax.deposit{value: 100 ether}(USER1_ADDRESS);
        stavax._setTotalControlled(100 ether);

        assertEq(stavax.totalSupply(), 100 ether);
        assertEq(stavax.balanceOf(USER1_ADDRESS), 100 ether);
    }

    function testSharesSingleUserBurn() public {
        stavax.deposit{value: 100 ether}(USER1_ADDRESS);
        stavax.withdraw(USER1_ADDRESS, 10 ether);
        stavax._setTotalControlled(90 ether);

        assertEq(stavax.totalSupply(), 90 ether);
        assertEq(stavax.balanceOf(USER1_ADDRESS), 90 ether);
    }

    function testSharesSingleUserNotEqual() public {
        stavax.deposit{value: 100 ether}(USER1_ADDRESS);
        stavax._setTotalControlled(50 ether);

        assertEq(stavax.balanceOf(USER1_ADDRESS), 50 ether);
    }

    function testSharesMultipleUser() public {
        stavax.deposit{value: 100 ether}(USER1_ADDRESS);
        stavax.deposit{value: 100 ether}(USER2_ADDRESS);

        stavax._setTotalControlled(100 ether);

        assertEq(stavax.balanceOf(USER1_ADDRESS), 50 ether);
        assertEq(stavax.balanceOf(USER2_ADDRESS), 50 ether);
    }

    function testSharesMultipleUserBurn() public {
        stavax.deposit{value: 100 ether}(USER1_ADDRESS);
        stavax.deposit{value: 100 ether}(USER2_ADDRESS);

        // Ater burn, USER1 has 60 AVAX remaining; total in protocol is now 160.
        stavax.withdraw(USER1_ADDRESS, 40 ether);

        assertEq(stavax.balanceOf(USER1_ADDRESS), 60 ether);
        assertEq(stavax.balanceOf(USER2_ADDRESS), 100 ether);
    }

    function testSharesMultipleUserNotEqual() public {
        stavax.deposit{value: 2 ether}(USER1_ADDRESS);
        stavax.deposit{value: 8 ether}(USER2_ADDRESS);
        stavax._setTotalControlled(50 ether);

        assertEq(stavax.balanceOf(USER1_ADDRESS), 10 ether);
        assertEq(stavax.balanceOf(USER2_ADDRESS), 40 ether);
    }

    function testSharesMultipleUserWithFuzzing(uint256 u1Amount, uint256 u2Amount) public {
        // AVAX total supply ~300m
        cheats.assume(u1Amount < 300_000_000 ether);
        cheats.assume(u2Amount < 300_000_000 ether);

        stavax.deposit{value: u1Amount}(USER1_ADDRESS);
        stavax.deposit{value: u2Amount}(USER2_ADDRESS);
        stavax._setTotalControlled(u1Amount + u2Amount);

        assertEq(stavax.balanceOf(USER1_ADDRESS), u1Amount);
        assertEq(stavax.balanceOf(USER2_ADDRESS), u2Amount);
    }

    function testSharesMultipleUserNotRound() public {
        stavax.deposit{value: 2 ether}(USER1_ADDRESS);
        stavax.deposit{value: 1 ether}(USER2_ADDRESS);

        stavax._setTotalControlled(100 ether);

        assertEq(stavax.balanceOf(USER1_ADDRESS), 66666666666666666666);
        assertEq(stavax.balanceOf(USER2_ADDRESS), 33333333333333333333);
    }

    function testTransferNoZero() public {
        stavax.deposit{value: 10 ether}(USER1_ADDRESS);

        cheats.prank(USER1_ADDRESS);
        cheats.expectRevert(stAVAX.CannotSendToZeroAddress.selector);
        stavax.transfer(ZERO_ADDRESS, 1 ether);

        // Original balance remains
        assertEq(stavax.balanceOf(USER1_ADDRESS), 10 ether);
    }

    function testTransferNoBalance() public {
        stavax.deposit{value: 10 ether}(DEPLOYER_ADDRESS);
        stavax.deposit{value: 2 ether}(USER1_ADDRESS);

        cheats.prank(USER1_ADDRESS);
        cheats.expectRevert(stAVAX.InsufficientSTAVAXBalance.selector);
        stavax.transfer(USER2_ADDRESS, 3 ether);

        // Original balance remains
        assertEq(stavax.balanceOf(USER1_ADDRESS), 2 ether);
    }

    function testTransfer() public {
        stavax.deposit{value: 2 ether}(USER1_ADDRESS);

        assertEq(stavax.balanceOf(USER1_ADDRESS), 2 ether);

        cheats.prank(USER1_ADDRESS);
        bool res = stavax.transfer(USER2_ADDRESS, 1 ether);
        assertTrue(res);

        assertEq(stavax.balanceOf(USER1_ADDRESS), 1 ether);
        assertEq(stavax.balanceOf(USER2_ADDRESS), 1 ether);
    }

    function testTransferMultipleDeposits() public {
        stavax.deposit{value: 0.5 ether}(USER1_ADDRESS);
        stavax.deposit{value: 0.5 ether}(USER1_ADDRESS);
        stavax.deposit{value: 0.5 ether}(USER1_ADDRESS);
        stavax.deposit{value: 0.5 ether}(USER1_ADDRESS);

        assertEq(stavax.balanceOf(USER1_ADDRESS), 2 ether);

        cheats.prank(USER1_ADDRESS);
        bool result = stavax.transfer(USER2_ADDRESS, 1 ether);
        assertTrue(result);

        assertEq(stavax.balanceOf(USER1_ADDRESS), 1 ether);
        assertEq(stavax.balanceOf(USER2_ADDRESS), 1 ether);

        cheats.prank(USER1_ADDRESS);
        result = stavax.transfer(USER2_ADDRESS, 1 ether);
        assertTrue(result);

        assertEq(stavax.balanceOf(USER1_ADDRESS), 0 ether);
        assertEq(stavax.balanceOf(USER2_ADDRESS), 2 ether);
    }

    function testTransferUnapproved() public {
        stavax.deposit{value: 1 ether}(USER1_ADDRESS);

        cheats.expectRevert(stAVAX.InsufficientSTAVAXAllowance.selector);
        stavax.transferFrom(USER1_ADDRESS, USER2_ADDRESS, 1 ether);
    }

    function testTransferApproved() public {
        stavax.deposit{value: 1 ether}(USER1_ADDRESS);

        cheats.prank(USER1_ADDRESS);
        stavax.approve(USER2_ADDRESS, 1 ether);

        cheats.prank(USER2_ADDRESS);
        stavax.transferFrom(USER1_ADDRESS, USER2_ADDRESS, 1 ether);
    }

    function testTransferApprovedInsufficent() public {
        stavax.deposit{value: 1 ether}(USER1_ADDRESS);

        cheats.prank(USER1_ADDRESS);
        stavax.approve(USER2_ADDRESS, 1 ether);

        cheats.prank(USER2_ADDRESS);
        cheats.expectRevert(stAVAX.InsufficientSTAVAXAllowance.selector);
        stavax.transferFrom(USER1_ADDRESS, USER2_ADDRESS, 10 ether);
    }
}
