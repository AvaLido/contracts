// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./helpers.sol";

import "../interfaces/ITreasury.sol";
import "../interfaces/ITreasuryBeneficiary.sol";
import "../Treasury.sol";
import "../AvaLido.sol";

contract FakeBeneficiary is ITreasuryBeneficiary {
    ITreasury treasury;

    function receiveFund() external payable {}

    function claimFromTreasury() external {
        uint256 val = address(treasury).balance;
        if (val == 0) return;
        treasury.claim(val);
    }

    function setTreasuryAddress(address _treasuryAddress) external {
        treasury = ITreasury(_treasuryAddress);
    }
}

contract TreasuryTest is DSTest, Helpers {
    ITreasury treasury;
    FakeBeneficiary beneficiary;

    function setUp() public {
        beneficiary = new FakeBeneficiary();
        treasury = new Treasury(address(beneficiary));
        beneficiary.setTreasuryAddress(address(treasury));
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
        beneficiary.claimFromTreasury();
        assertEq(address(treasury).balance, 0 ether);
        assertEq(address(beneficiary).balance, 1 ether);
    }

    function testNonBeneficiaryCannotClaimFromTreasury() public {
        payable(address(treasury)).transfer(1 ether);
        assertEq(address(treasury).balance, 1 ether);
        vm.expectRevert(Treasury.BeneficiaryOnly.selector);
        treasury.claim(1 ether);
    }
}
