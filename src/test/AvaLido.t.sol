// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
// import "ds-test/src/test.sol";
import "../AvaLido.sol";
import "../interfaces/IOracle.sol";

import "./console.sol";
import "./cheats.sol";
import "./helpers.sol";

import "openzeppelin-contracts/contracts/finance/PaymentSplitter.sol";

contract AvaLidoTest is DSTest, Helpers {
    event StakeEvent(uint256 indexed amount, string indexed validator, uint256 stakeStartTime, uint256 stakeEndTime);
    event RewardsCollectedEvent(uint256 amount);
    event ProtocolFeeEvent(uint256 amount);

    AvaLido lido;
    ValidatorSelector validatorSelector;

    address feeAddressAuthor = 0x1000000000000000000000000000000000000001;
    address feeAddressLido = 0x1000000000000000000000000000000000000002;
    address mpcWalletAddress = 0x1000000000000000000000000000000000000004;
    address validatorSelectorAddress;

    function setUp() public {
        // Not an actual oracle contract, but calls to ValidatorSelector should all be stubbed.
        IOracle oracle = IOracle(0x9000000000000000000000000000000000000001);
        validatorSelector = new ValidatorSelector(oracle);
        validatorSelectorAddress = address(validatorSelector);

        lido = new AvaLido(feeAddressLido, feeAddressAuthor, validatorSelectorAddress, mpcWalletAddress);
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

    // Initiate staking

    function testInitiateStakeZero() public {
        uint256 staked = lido.initiateStake();
        assertEq(staked, 0);
    }

    function testInitiateStakeNoValidators() public {
        lido.deposit{value: 10 ether}();

        string[] memory idResult = new string[](0);
        uint256[] memory amountResult = new uint256[](0);

        cheats.mockCall(
            validatorSelectorAddress,
            abi.encodeWithSelector(lido.validatorSelector().selectValidatorsForStake.selector),
            abi.encode(idResult, amountResult, 10 ether)
        );

        cheats.expectRevert(AvaLido.NoAvailableValidators.selector);
        lido.initiateStake();
    }

    // TODO: figure out why this is failing on Github actions but not locally
    // function testInitiateStakeFullAllocation() public {
    //     lido.deposit{value: 10 ether}();

    //     validatorSelectMock(validatorSelectorAddress, "test-node", 10 ether, 0);

    //     cheats.expectEmit(true, true, false, true);
    //     emit StakeEvent(10 ether, "test-node", 1800, 1211400);

    //     uint256 staked = lido.initiateStake();
    //     assertEq(staked, 10 ether);
    //     assertEq(address(mpcWalletAddress).balance, 10 ether);
    // }

    function testInitiateStakePartialAllocation() public {
        lido.deposit{value: 10 ether}();

        validatorSelectMock(validatorSelectorAddress, "test-node", 9 ether, 1 ether);
        uint256 staked = lido.initiateStake();
        assertEq(staked, 9 ether);
        assertEq(address(mpcWalletAddress).balance, 9 ether);
        assertEq(lido.amountPendingAVAX(), 1 ether);
    }

    function testInitiateStakeUnderLimit() public {
        lido.deposit{value: 1 ether}();
        uint256 staked = lido.initiateStake();
        assertEq(staked, 0);
        assertEq(lido.amountPendingAVAX(), 1 ether);
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
        lido.deposit{value: 10 ether}();
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        assertEq(lido.balanceOf(TEST_ADDRESS), 10 ether);

        uint256 requestId = lido.requestWithdrawal(5 ether);
        assertEq(requestId, 0);
        assertEq(lido.balanceOf(TEST_ADDRESS), 5 ether);

        (
            address requester,
            uint64 requestAt,
            uint256 amountRequested,
            uint256 amountFilled,
            uint256 amountClaimed
        ) = lido.unstakeRequests(requestId);

        assertEq(requester, TEST_ADDRESS);
        assertEq(requestAt, uint64(block.timestamp));
        assertEq(amountRequested, 5 ether);
        assertEq(amountFilled, 0 ether);
        assertEq(amountClaimed, 0 ether);

        uint256 requestId2 = lido.requestWithdrawal(1 ether);
        (
            address requester2,
            uint256 requestAt2,
            uint256 amountRequested2,
            uint256 amountFilled2,
            uint256 amountClaimed2
        ) = lido.unstakeRequests(requestId2);

        assertEq(requestId2, 1);
        assertEq(lido.balanceOf(TEST_ADDRESS), 4 ether);

        assertEq(requester2, TEST_ADDRESS);
        assertEq(requestAt2, uint64(block.timestamp));
        assertEq(amountRequested2, 1 ether);
        assertEq(amountFilled2, 0 ether);
        assertEq(amountClaimed2, 0 ether);
    }

    function testFillUnstakeRequestSingle() public {
        lido.deposit{value: 10 ether}();
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        lido.requestWithdrawal(0.5 ether);
        lido.receivePrincipalFromMPC{value: 0.5 ether}();

        (, , uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(0);

        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.5 ether);
    }

    function testMultipleFillUnstakeRequestsSingleFill() public {
        lido.deposit{value: 10 ether}();
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

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
        lido.deposit{value: 10 ether}();
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        uint256 reqId = lido.requestWithdrawal(0.5 ether);
        lido.receivePrincipalFromMPC{value: 0.1 ether}();

        (, , uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(reqId);

        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.1 ether);
    }

    function testFillUnstakeRequestPartialMultiple() public {
        lido.deposit{value: 10 ether}();
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        lido.requestWithdrawal(0.5 ether);
        lido.receivePrincipalFromMPC{value: 0.1 ether}();
        lido.receivePrincipalFromMPC{value: 0.1 ether}();

        (, , uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(0);

        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.2 ether);
    }

    function testFillUnstakeRequestPartialMultipleFilled() public {
        lido.deposit{value: 10 ether}();
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

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
        lido.deposit{value: 10 ether}();
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

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
        lido.deposit{value: 10 ether}();
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

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
        cheats.assume(x > lido.minStakeBatchAmount());
        cheats.assume(x < MAXIMUM_STAKE_AMOUNT);

        lido.deposit{value: x}();
        validatorSelectMock(validatorSelectorAddress, "test", x, 0);
        lido.initiateStake();

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
        lido.deposit{value: 10 ether}();
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        uint256 reqId = lido.requestWithdrawal(0.5 ether);
        lido.receivePrincipalFromMPC{value: 0.5 ether}();

        // Make a request as somebody else
        cheats.prank(ZERO_ADDRESS);
        cheats.expectRevert(AvaLido.NotAuthorized.selector);
        lido.claim(reqId, 0.5 ether);
    }

    function testClaimTooLarge() public {
        lido.deposit{value: 10 ether}();
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        uint256 reqId = lido.requestWithdrawal(0.5 ether);
        lido.receivePrincipalFromMPC{value: 0.5 ether}();

        cheats.expectRevert(AvaLido.ClaimTooLarge.selector);
        lido.claim(reqId, 1 ether);
    }

    function testClaimSucceeds() public {
        cheats.deal(TEST_ADDRESS, 10 ether);

        lido.deposit{value: 10 ether}();
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        // No longer has any AVAX, but has stAVAX
        assertEq(address(TEST_ADDRESS).balance, 0);
        assertEq(lido.balanceOf(TEST_ADDRESS), 10 ether);

        uint256 reqId = lido.requestWithdrawal(4 ether);

        // Some stAVAX is transferred to contract when requesting withdrawal.
        assertEq(lido.balanceOf(TEST_ADDRESS), 6 ether);

        cheats.deal(mpcWalletAddress, 5 ether);
        cheats.prank(mpcWalletAddress);
        lido.receivePrincipalFromMPC{value: 5 ether}();

        assertEq(lido.unstakeRequestCount(TEST_ADDRESS), 1);
        lido.claim(reqId, 4 ether);
        assertEq(lido.unstakeRequestCount(TEST_ADDRESS), 0);

        // Has the AVAX they claimed back.
        assertEq(address(TEST_ADDRESS).balance, 4 ether);

        // Still has remaming stAVAX
        assertEq(lido.balanceOf(TEST_ADDRESS), 6 ether);

        (address requester, , uint256 amountRequested, , uint256 amountClaimed) = lido.unstakeRequests(reqId);

        // Full claim so expect the data to be removed.
        assertEq(requester, ZERO_ADDRESS);
        assertEq(amountRequested, 0);
        assertEq(amountClaimed, 0);
    }

    function testPartialClaimSucceeds() public {
        lido.deposit{value: 10 ether}();
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

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
        lido.deposit{value: 10 ether}();
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

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

        cheats.assume(x > lido.minStakeBatchAmount());
        cheats.assume(x < MAXIMUM_STAKE_AMOUNT);

        lido.deposit{value: x}();
        validatorSelectMock(validatorSelectorAddress, "test", x, 0);
        lido.initiateStake();

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
        assertEq(lido.protocolControlledAVAX(), 0);
        assertEq(lido.amountPendingAVAX(), 0);

        cheats.expectEmit(false, false, false, true);
        emit ProtocolFeeEvent(0.1 ether);

        cheats.expectEmit(false, false, false, true);
        emit RewardsCollectedEvent(0.9 ether);

        lido.receiveRewardsFromMPC{value: 1 ether}();

        assertEq(lido.protocolControlledAVAX(), 0.9 ether);
        assertEq(lido.amountPendingAVAX(), 0.9 ether);

        assertEq(address(lido.protocolFeeSplitter()).balance, 0.1 ether);

        PaymentSplitter splitter = PaymentSplitter(lido.protocolFeeSplitter());

        splitter.release(payable(feeAddressAuthor));
        splitter.release(payable(feeAddressLido));

        assertEq(address(feeAddressAuthor).balance, 0.02 ether);
        assertEq(address(feeAddressLido).balance, 0.08 ether);
    }

    function testRewardsReceivedFillUnstakeRequests() public {
        lido.deposit{value: 10 ether}();
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);

        lido.initiateStake();

        uint256 requestId = lido.requestWithdrawal(5 ether);

        lido.receiveRewardsFromMPC{value: 1 ether}();

        // 0.1 taken as fee, 0.9 should be used to fill requests.
        (, , uint256 amountRequested, uint256 amountFilled, uint256 amountClaimed) = lido.unstakeRequests(requestId);

        assertEq(amountRequested, 5 ether);
        assertEq(amountFilled, 0.9 ether);
        assertEq(amountClaimed, 0 ether);
    }
}
