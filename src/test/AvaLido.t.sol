// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "../AvaLido.sol";

contract AvaLidoTest is DSTest {
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

        lido.requestWithdrawal(0.5 ether);

        // uint32 requestId = lido.userRequests(msg.sender, 0);
        // assertEq(requestId, 0);

        // TODO: broken
        (address requester, uint32 id, uint256 amountRequested, uint256 amountFilled, uint256 requestAt) = lido
            .unstakeRequests(0);
        assertEq(requester, msg.sender);
    }
}
