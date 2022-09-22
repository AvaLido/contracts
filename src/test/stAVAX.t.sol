// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {Test} from "forge-std/Test.sol";

import "./helpers.sol";

import "../stAVAX.sol";

contract TestToken is stAVAX {
    uint256 public totalControlled = 0;

    function protocolControlledAVAX() public view override returns (uint256) {
        return totalControlled;
    }

    function deposit(address sender) public payable {
        uint256 amount = msg.value;
        totalControlled += amount;
        uint256 stAVAXAmount = avaxToStAVAX(protocolControlledAVAX() - amount, amount);
        if (stAVAXAmount == 0) {
            // `stAVAXAmount` is 0: this is the first ever deposit. Assume that stAVAX amount corresponds to AVAX 1-to-1.
            stAVAXAmount = amount;
        }
        _mint(sender, stAVAXAmount);
    }

    function withdraw(address owner, uint256 stAVAXAmount) public {
        uint256 amount = stAVAXToAVAX(protocolControlledAVAX(), stAVAXAmount);
        _burn(owner, amount);
        totalControlled -= amount;
    }
}

contract stAVAXTest is Test, Helpers {
    TestToken stavax;

    function setUp() public {
        stavax = new TestToken();
    }

    function testDepositSingleUser() public {
        stavax.deposit{value: 100 ether}(USER1_ADDRESS);

        assertEq(stavax.totalSupply(), 100 ether);
        assertEq(stavax.balanceOf(USER1_ADDRESS), 100 ether);
    }

    function testDepositSingleUserBurn() public {
        stavax.deposit{value: 100 ether}(USER1_ADDRESS);
        stavax.withdraw(USER1_ADDRESS, 10 ether);

        assertEq(stavax.totalSupply(), 90 ether);
        assertEq(stavax.balanceOf(USER1_ADDRESS), 90 ether);
    }

    function testDepositMultipleUserBurn() public {
        stavax.deposit{value: 100 ether}(USER1_ADDRESS);
        stavax.deposit{value: 100 ether}(USER2_ADDRESS);

        // Ater burn, USER1 has 60 AVAX remaining; total in protocol is now 160.
        stavax.withdraw(USER1_ADDRESS, 40 ether);

        assertEq(stavax.balanceOf(USER1_ADDRESS), 60 ether);
        assertEq(stavax.balanceOf(USER2_ADDRESS), 100 ether);
    }

    function testDepositMultipleUserWithFuzzing(uint256 u1Amount, uint256 u2Amount) public {
        // AVAX total supply ~300m
        vm.assume(u1Amount < 300_000_000 ether);
        vm.assume(u2Amount < 300_000_000 ether);

        // Prevent fuzzing triggering zero exchange rate.
        vm.assume(u1Amount > 0);
        vm.assume(u2Amount > 0);

        stavax.deposit{value: u1Amount}(USER1_ADDRESS);
        stavax.deposit{value: u2Amount}(USER2_ADDRESS);

        assertEq(stavax.balanceOf(USER1_ADDRESS), u1Amount);
        assertEq(stavax.balanceOf(USER2_ADDRESS), u2Amount);
    }

    function testTransferNoZero() public {
        stavax.deposit{value: 10 ether}(USER1_ADDRESS);

        vm.prank(USER1_ADDRESS);
        vm.expectRevert("ERC20: transfer to the zero address");
        stavax.transfer(ZERO_ADDRESS, 1 ether);

        // Original balance remains
        assertEq(stavax.balanceOf(USER1_ADDRESS), 10 ether);
    }

    function testTransferNoBalance() public {
        stavax.deposit{value: 2 ether}(USER1_ADDRESS);
        stavax.deposit{value: 10 ether}(USER2_ADDRESS);

        vm.prank(USER1_ADDRESS);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        stavax.transfer(USER2_ADDRESS, 3 ether);

        // Original balance remains
        assertEq(stavax.balanceOf(USER1_ADDRESS), 2 ether);
    }

    function testTransfer() public {
        stavax.deposit{value: 2 ether}(USER1_ADDRESS);

        assertEq(stavax.balanceOf(USER1_ADDRESS), 2 ether);

        vm.prank(USER1_ADDRESS);
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

        vm.prank(USER1_ADDRESS);
        bool result = stavax.transfer(USER2_ADDRESS, 1 ether);
        assertTrue(result);

        assertEq(stavax.balanceOf(USER1_ADDRESS), 1 ether);
        assertEq(stavax.balanceOf(USER2_ADDRESS), 1 ether);

        vm.prank(USER1_ADDRESS);
        result = stavax.transfer(USER2_ADDRESS, 1 ether);
        assertTrue(result);

        assertEq(stavax.balanceOf(USER1_ADDRESS), 0 ether);
        assertEq(stavax.balanceOf(USER2_ADDRESS), 2 ether);
    }

    function testTransferUnapproved() public {
        stavax.deposit{value: 1 ether}(USER1_ADDRESS);

        vm.expectRevert("ERC20: insufficient allowance");
        stavax.transferFrom(USER1_ADDRESS, USER2_ADDRESS, 1 ether);
    }

    function testTransferApproved() public {
        stavax.deposit{value: 1 ether}(USER1_ADDRESS);

        vm.prank(USER1_ADDRESS);
        stavax.approve(USER2_ADDRESS, 1 ether);

        vm.prank(USER2_ADDRESS);
        stavax.transferFrom(USER1_ADDRESS, USER2_ADDRESS, 1 ether);
    }

    function testTransferApprovedInsufficent() public {
        stavax.deposit{value: 1 ether}(USER1_ADDRESS);

        vm.prank(USER1_ADDRESS);
        stavax.approve(USER2_ADDRESS, 1 ether);

        vm.prank(USER2_ADDRESS);
        vm.expectRevert("ERC20: insufficient allowance");
        stavax.transferFrom(USER1_ADDRESS, USER2_ADDRESS, 10 ether);
    }
}
