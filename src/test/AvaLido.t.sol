// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "../AvaLido.sol";
import "./console.sol";
import "./cheats.sol";

import "openzeppelin-contracts/contracts/finance/PaymentSplitter.sol";

address constant ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;
address constant USER1_ADDRESS = 0x0000000000000000000000000000000000000001;
address constant USER2_ADDRESS = 0x0000000000000000000000000000000000000002;

contract AvaLidoTest is DSTest {
    event StakeEvent(uint256 amount);

    AvaLido lido;

    address feeAddressHE = 0x0000000000000000000000000000000000000001;
    address feeAddressLido = 0x0000000000000000000000000000000000000002;

    function setUp() public {
        lido = new AvaLido(feeAddressLido, feeAddressHE);
    }

    receive() external payable {}

    // Deposit

    function testStakeBasic() public {
        lido.deposit{value: 1 ether}();
        assertEq(lido.balanceOf(TEST_ADDRESS), 1 ether);
    }

    function testStakeZeroDeposit() public {
        cheats.expectRevert(AvaLido.InvalidStakeAmount.selector);
        lido.deposit{value: 0 ether}();
    }

    function testStakeTooLargeDeposit() public {
        cheats.expectRevert(AvaLido.InvalidStakeAmount.selector);
        lido.deposit{value: (MAXIMUM_STAKE_AMOUNT + 1)}();
    }

    function testStakeWithFuzzing(uint256 x) public {
        cheats.deal(TEST_ADDRESS, type(uint256).max);

        cheats.assume(x > MINIMUM_STAKE_AMOUNT);
        cheats.assume(x < MAXIMUM_STAKE_AMOUNT);
        lido.deposit{value: x}();
        assertEq(lido.balanceOf(TEST_ADDRESS), x);
    }

    // Unstake Requests

    function testUnstakeRequestZeroAmount() public {
        cheats.expectRevert(AvaLido.InvalidStakeAmount.selector);
        lido.requestWithdrawal(0 ether);
    }

    function testTooManyConcurrentUnstakes() public {
        lido.deposit{value: 100 ether}();
        // Do all the allowed requests
        for (uint256 i = 1; i <= MAXIMUM_UNSTAKE_REQUESTS; i++) {
            lido.requestWithdrawal(1 ether);
        }
        // Try one more
        cheats.expectRevert(AvaLido.TooManyConcurrentUnstakeRequests.selector);
        lido.requestWithdrawal(1 ether);
    }

    function testUnstakeRequest() public {
        lido.deposit{value: 1 ether}();
        // TODO: Test stAVAX transfer.

        uint256 requestId = lido.requestWithdrawal(0.5 ether);
        assertEq(requestId, 0);

        (
            address requester,
            uint64 requestAt,
            uint256 amountRequested,
            uint256 amountFilled,
            uint256 amountClaimed
        ) = lido.unstakeRequests(requestId);

        assertEq(requester, TEST_ADDRESS);
        assertEq(requestAt, uint64(block.timestamp));
        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0 ether);
        assertEq(amountClaimed, 0 ether);

        uint256 requestId2 = lido.requestWithdrawal(0.1 ether);
        (
            address requester2,
            uint256 requestAt2,
            uint256 amountRequested2,
            uint256 amountFilled2,
            uint256 amountClaimed2
        ) = lido.unstakeRequests(requestId2);

        assertEq(requestId2, 1);

        assertEq(requester2, TEST_ADDRESS);
        assertEq(requestAt2, uint64(block.timestamp));
        assertEq(amountRequested2, 0.1 ether);
        assertEq(amountFilled2, 0 ether);
        assertEq(amountClaimed2, 0 ether);
    }

    function testFillUnstakeRequestSingle() public {
        lido.deposit{value: 1 ether}();
        lido.requestWithdrawal(0.5 ether);
        lido.receivePrincipalFromMPC{value: 0.5 ether}();

        (, , uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(0);

        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.5 ether);
    }

    function testMultipleFillUnstakeRequestsSingleFill() public {
        lido.deposit{value: 1 ether}();
        lido.requestWithdrawal(0.5 ether);
        lido.requestWithdrawal(0.25 ether);
        lido.requestWithdrawal(0.1 ether);
        lido.receivePrincipalFromMPC{value: 1 ether}();

        (, , uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(0);
        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.5 ether);

        (, , uint256 amountRequested2, uint256 amountFilled2, ) = lido.unstakeRequests(1);
        assertEq(amountRequested2, 0.25 ether);
        assertEq(amountFilled2, 0.25 ether);

        (, , uint256 amountRequested3, uint256 amountFilled3, ) = lido.unstakeRequests(2);
        assertEq(amountRequested3, 0.1 ether);
        assertEq(amountFilled3, 0.1 ether);
    }

    function testFillUnstakeRequestPartial() public {
        lido.deposit{value: 1 ether}();
        uint256 reqId = lido.requestWithdrawal(0.5 ether);
        lido.receivePrincipalFromMPC{value: 0.1 ether}();

        (, , uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(reqId);

        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.1 ether);
    }

    function testFillUnstakeRequestPartialMultiple() public {
        lido.deposit{value: 1 ether}();
        lido.requestWithdrawal(0.5 ether);
        lido.receivePrincipalFromMPC{value: 0.1 ether}();
        lido.receivePrincipalFromMPC{value: 0.1 ether}();

        (, , uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(0);

        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.2 ether);
    }

    function testFillUnstakeRequestPartialMultipleFilled() public {
        lido.deposit{value: 1 ether}();
        lido.requestWithdrawal(0.5 ether);
        lido.receivePrincipalFromMPC{value: 0.1 ether}();

        // TODO: Fix issue with test
        // cheats.expectEmit(true, false, false, false);
        // emit StakeEvent(0.6 ether);

        lido.receivePrincipalFromMPC{value: 0.9 ether}();

        (, , uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(0);

        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.5 ether);
    }

    function testFillUnstakeRequestMultiRequestSingleFill() public {
        lido.deposit{value: 1 ether}();
        uint256 req1 = lido.requestWithdrawal(0.5 ether);
        uint256 req2 = lido.requestWithdrawal(0.5 ether);
        lido.receivePrincipalFromMPC{value: 0.5 ether}();

        (, , uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(req1);
        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.5 ether);

        (, , uint256 amountRequested2, uint256 amountFilled2, ) = lido.unstakeRequests(req2);
        assertEq(amountRequested2, 0.5 ether);
        assertEq(amountFilled2, 0);
    }

    function testMultipleRequestReads() public {
        lido.deposit{value: 1 ether}();
        uint256 reqId = lido.requestWithdrawal(0.5 ether);

        // Make a request as somebody else
        cheats.deal(USER1_ADDRESS, 0.2 ether);
        cheats.startPrank(USER1_ADDRESS);
        lido.deposit{value: 0.2 ether}();
        lido.requestWithdrawal(0.2 ether);
        cheats.stopPrank();

        // Make another request as the original user.
        uint256 reqId2 = lido.requestWithdrawal(0.2 ether);

        assertEq(reqId, 0);
        // Ensure that the next id for the user is the 3rd overall, not second.
        assertEq(reqId2, 2);
    }

    function testUnstakeRequestFillWithFuzzing(uint256 x) public {
        cheats.deal(TEST_ADDRESS, type(uint256).max);
        cheats.assume(x > MINIMUM_STAKE_AMOUNT);
        cheats.assume(x < MAXIMUM_STAKE_AMOUNT);

        lido.deposit{value: x}();

        uint256 requestId = lido.requestWithdrawal(x);
        assertEq(requestId, 0);

        cheats.deal(ZERO_ADDRESS, type(uint256).max);
        console.log(ZERO_ADDRESS.balance);

        cheats.prank(ZERO_ADDRESS);
        lido.receivePrincipalFromMPC{value: x}();

        (, , uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(0);

        assertEq(amountRequested, x);
        assertEq(amountFilled, x);
    }

    // Claiming

    function testClaimOwnedByOtherUser() public {
        lido.deposit{value: 1 ether}();
        uint256 reqId = lido.requestWithdrawal(0.5 ether);
        lido.receivePrincipalFromMPC{value: 0.5 ether}();

        // Make a request as somebody else
        cheats.prank(ZERO_ADDRESS);
        cheats.expectRevert(AvaLido.NotAuthorized.selector);
        lido.claim(reqId, 0.5 ether);
    }

    function testClaimTooLarge() public {
        lido.deposit{value: 1 ether}();
        uint256 reqId = lido.requestWithdrawal(0.5 ether);
        lido.receivePrincipalFromMPC{value: 0.5 ether}();

        cheats.expectRevert(AvaLido.ClaimTooLarge.selector);
        lido.claim(reqId, 1 ether);
    }

    function testClaimSucceeds() public {
        lido.deposit{value: 1 ether}();
        uint256 reqId = lido.requestWithdrawal(0.5 ether);
        lido.receivePrincipalFromMPC{value: 0.5 ether}();

        assertEq(lido.unstakeRequestCount(TEST_ADDRESS), 1);
        lido.claim(reqId, 0.5 ether);
        assertEq(lido.unstakeRequestCount(TEST_ADDRESS), 0);

        (address requester, , uint256 amountRequested, , uint256 amountClaimed) = lido.unstakeRequests(reqId);

        // Full claim so expect the data to be removed.
        assertEq(requester, ZERO_ADDRESS);
        assertEq(amountRequested, 0);
        assertEq(amountClaimed, 0);
    }

    function testPartialClaimSucceeds() public {
        lido.deposit{value: 1 ether}();
        uint256 reqId = lido.requestWithdrawal(1 ether);
        lido.receivePrincipalFromMPC{value: 1 ether}();

        assertEq(lido.unstakeRequestCount(TEST_ADDRESS), 1);
        lido.claim(reqId, 0.5 ether);

        // Request should still be there.
        assertEq(lido.unstakeRequestCount(TEST_ADDRESS), 1);

        (, , uint256 amountRequested, uint256 amountFilled, uint256 amountClaimed) = lido.unstakeRequests(reqId);

        assertEq(amountRequested, 1 ether);
        assertEq(amountFilled, 1 ether);
        assertEq(amountClaimed, 0.5 ether);
    }

    function testMultiplePartialClaims() public {
        lido.deposit{value: 1 ether}();
        uint256 reqId = lido.requestWithdrawal(1 ether);
        lido.receivePrincipalFromMPC{value: 1 ether}();

        assertEq(lido.unstakeRequestCount(TEST_ADDRESS), 1);
        lido.claim(reqId, 0.5 ether);

        // Request should still be there.
        assertEq(lido.unstakeRequestCount(TEST_ADDRESS), 1);

        (, , uint256 amountRequested, uint256 amountFilled, uint256 amountClaimed) = lido.unstakeRequests(reqId);

        assertEq(amountRequested, 1 ether);
        assertEq(amountFilled, 1 ether);
        assertEq(amountClaimed, 0.5 ether);

        lido.claim(reqId, 0.25 ether);

        (, , , , uint256 amountClaimed2) = lido.unstakeRequests(reqId);
        assertEq(amountClaimed2, 0.75 ether);

        lido.claim(reqId, 0.25 ether);
        assertEq(lido.unstakeRequestCount(TEST_ADDRESS), 0);

        (address requester, , , , ) = lido.unstakeRequests(reqId);

        // Full claim so expect the data to be removed.
        assertEq(requester, ZERO_ADDRESS);
    }

    function testClaimWithFuzzing(uint256 x) public {
        cheats.deal(TEST_ADDRESS, type(uint256).max);

        cheats.assume(x > MINIMUM_STAKE_AMOUNT);
        cheats.assume(x < MAXIMUM_STAKE_AMOUNT);

        lido.deposit{value: x}();
        uint256 reqId = lido.requestWithdrawal(x);
        lido.receivePrincipalFromMPC{value: x}();

        lido.claim(reqId, x);

        // TODO: Assert tokens transferred correctly
    }

    // Tokens

    function protocolControlledAVAX() public {
        lido.deposit{value: 1 ether}();
        assertEq(lido.protocolControlledAVAX(), 1 ether);

        lido.receivePrincipalFromMPC{value: 0.6 ether}();
        assertEq(lido.protocolControlledAVAX(), 0.4 ether);

        lido.receivePrincipalFromMPC{value: 0.4 ether}();
        assertEq(lido.protocolControlledAVAX(), 0 ether);
    }

    function testRewardReceived() public {
        lido.receiveRewardsFromMPC{value: 1 ether}();

        assertEq(address(lido.protocolFeeSplitter()).balance, 0.1 ether);

        PaymentSplitter splitter = PaymentSplitter(lido.protocolFeeSplitter());

        splitter.release(payable(feeAddressHE));
        splitter.release(payable(feeAddressLido));

        assertEq(address(feeAddressHE).balance, 0.02 ether);
        assertEq(address(feeAddressLido).balance, 0.08 ether);
    }
}
