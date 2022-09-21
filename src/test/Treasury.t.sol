// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

import "../interfaces/ITreasury.sol";
import "../Treasury.sol";

contract TreasuryTest is Test {
    address constant AVALIDO_ADDRESS = 0x1000000000000000000000000000000000012345;
    address constant NON_AVALIDO_ADDRESS = 0x1111111111111111111111111111111111111111;

    ITreasury treasury;

    function setUp() public {
        treasury = new Treasury(AVALIDO_ADDRESS);
    }

    // -------------------------------------------------------------------------
    //  Test cases
    // -------------------------------------------------------------------------
    function testCanSendToTreasury() public {
        payable(address(treasury)).transfer(1 ether);
        assertEq(address(treasury).balance, 1 ether);
    }

    function testCanClaimFromTreasury() public {
        payable(address(treasury)).transfer(1 ether);
        assertEq(address(treasury).balance, 1 ether);
        vm.prank(AVALIDO_ADDRESS);
        treasury.claim(1 ether);
        assertEq(address(treasury).balance, 0 ether);
        assertEq(address(AVALIDO_ADDRESS).balance, 1 ether);
    }

    function testNonBeneficiaryCannotClaimFromTreasury() public {
        payable(address(treasury)).transfer(1 ether);
        assertEq(address(treasury).balance, 1 ether);
        vm.prank(NON_AVALIDO_ADDRESS);
        vm.expectRevert(Treasury.BeneficiaryOnly.selector);
        treasury.claim(1 ether);
    }
}
