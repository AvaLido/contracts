// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "../AvaLido.sol";
import "./console.sol";
import "./cheats.sol";

address constant ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;

contract AvaLidoTest is DSTest {
    event StakeEvent(uint256 amount);

    AvaLido lido;

    function setUp() public {
        lido = new AvaLido();
    }

    // Deposit

    function testStakeBasic() public {
        lido.deposit{value: 1 ether}(1 ether);
    }

    function testFailStakeNotEnoughAVAX() public {
        lido.deposit{value: 0.9 ether}(1 ether);
    }

    function testFailStakeZeroDeposit() public {
        lido.deposit{value: 0 ether}(0 ether);
    }

    // Unstake Requests

    function testUnstakeRequest() public {
        lido.deposit{value: 1 ether}(1 ether);
        // TODO: Test stAVAX transfer.

        uint256 requestId = lido.requestWithdrawal(0.5 ether);
        assertEq(requestId, 0);

        (address requester, uint256 amountRequested, uint256 amountFilled, uint256 requestAt) = lido.unstakeRequests(
            requestId
        );

        assertEq(requester, TEST_ADDRESS);
        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0 ether);
        assertEq(requestAt, block.timestamp);

        uint256 requestId2 = lido.requestWithdrawal(0.1 ether);
        (address requester2, uint256 amountRequested2, uint256 amountFilled2, uint256 requestAt2) = lido
            .unstakeRequests(requestId2);

        assertEq(requestId2, 1);

        assertEq(requester2, TEST_ADDRESS);
        assertEq(amountRequested2, 0.1 ether);
        assertEq(amountFilled2, 0 ether);
        assertEq(requestAt2, block.timestamp);
    }

    function testFillUnstakeRequestSingle() public {
        lido.deposit{value: 1 ether}(1 ether);
        lido.requestWithdrawal(0.5 ether);
        lido.receiveFromMPC{value: 0.5 ether}();

        (, uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(0);

        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.5 ether);
    }

    function testMultipleFillUnstakeRequestsSingleFill() public {
        lido.deposit{value: 1 ether}(1 ether);
        lido.requestWithdrawal(0.5 ether);
        lido.requestWithdrawal(0.25 ether);
        lido.requestWithdrawal(0.1 ether);
        lido.receiveFromMPC{value: 2 ether}();

        (, uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(0);
        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.5 ether);

        (, uint256 amountRequested2, uint256 amountFilled2, ) = lido.unstakeRequests(1);
        assertEq(amountRequested2, 0.25 ether);
        assertEq(amountFilled2, 0.25 ether);

        (, uint256 amountRequested3, uint256 amountFilled3, ) = lido.unstakeRequests(2);
        assertEq(amountRequested3, 0.1 ether);
        assertEq(amountFilled3, 0.1 ether);
    }

    function testFillUnstakeRequestPartial() public {
        lido.deposit{value: 1 ether}(1 ether);
        uint256 reqId = lido.requestWithdrawal(0.5 ether);
        lido.receiveFromMPC{value: 0.1 ether}();

        (, uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(reqId);

        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.1 ether);
    }

    function testFillUnstakeRequestPartialMultiple() public {
        lido.deposit{value: 1 ether}(1 ether);
        lido.requestWithdrawal(0.5 ether);
        lido.receiveFromMPC{value: 0.1 ether}();
        lido.receiveFromMPC{value: 0.1 ether}();

        (, uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(0);

        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.2 ether);
    }

    function testFillUnstakeRequestPartialMultipleFilled() public {
        lido.deposit{value: 1 ether}(1 ether);
        lido.requestWithdrawal(0.5 ether);
        lido.receiveFromMPC{value: 0.1 ether}();

        // TODO: Fix issue with test
        // cheats.expectEmit(true, false, false, false);
        // emit StakeEvent(0.6 ether);

        lido.receiveFromMPC{value: 1 ether}();

        (, uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(0);

        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.5 ether);
    }

    function testMultipleRequestReads() public {
        lido.deposit{value: 1 ether}(1 ether);
        uint256 reqId = lido.requestWithdrawal(0.5 ether);

        // Make a request as somebody else
        cheats.prank(ZERO_ADDRESS);
        lido.requestWithdrawal(0.1 ether);

        // Make another request as the original user.
        uint256 reqId2 = lido.requestWithdrawal(0.2 ether);

        assertEq(reqId, 0);
        // Ensure that the next id for the user is the 3rd overall, not second.
        assertEq(reqId2, 2);
    }
}
