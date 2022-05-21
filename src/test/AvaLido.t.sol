// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "../AvaLido.sol";
import "../interfaces/IOracle.sol";

import "./helpers.sol";

import "openzeppelin-contracts/contracts/finance/PaymentSplitter.sol";

contract AvaLidoTest is DSTest, Helpers {
    event StakeEvent(uint256 indexed amount, string indexed validator, uint256 stakeStartTime, uint256 stakeEndTime);
    event RewardsCollectedEvent(uint256 amount);
    event ProtocolFeeEvent(uint256 amount);
    event RequestFullyFilledEvent(uint256 indexed requestedAmount, uint256 timestamp, uint256 requestIndex);
    event RequestPartiallyFilledEvent(uint256 indexed fillAmount, uint256 timestamp, uint256 requestIndex);

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
        assertEq(lido.balanceOf(DEPLOYER_ADDRESS), 1 ether);
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
        cheats.deal(DEPLOYER_ADDRESS, type(uint256).max);

        cheats.assume(x > MINIMUM_STAKE_AMOUNT);
        cheats.assume(x < MAXIMUM_STAKE_AMOUNT);
        lido.deposit{value: x}();
        assertEq(lido.balanceOf(DEPLOYER_ADDRESS), x);
    }

    function testStakeAlsoFillsUnstakeRequests() public {
        // Deposit as user 1.
        cheats.prank(USER1_ADDRESS);
        cheats.deal(USER1_ADDRESS, 10 ether);
        lido.deposit{value: 10 ether}();

        // Test the amountPendingAVAX the contract has
        assertEq(10 ether, lido.amountPendingAVAX());

        // Set up validator and stake.
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        // Test the amountPendingAVAX the contract has - all should have been staked
        assertEq(0 ether, lido.amountPendingAVAX());

        // User 1 requests a withdrawal of 2 ether
        cheats.prank(USER1_ADDRESS);
        lido.requestWithdrawal(2 ether);
        cheats.expectEmit(true, false, false, true);
        emit RequestPartiallyFilledEvent(1 ether, uint64(block.timestamp), 0);
        lido.receivePrincipalFromMPC{value: 1 ether}();

        // Test that user 1's request has been partially filled
        (
            address requester,
            uint64 requestAt,
            uint256 amountRequested,
            uint256 amountFilled,
            uint256 amountClaimed
        ) = lido.unstakeRequests(0);

        assertEq(requester, USER1_ADDRESS);
        assertEq(requestAt, uint64(block.timestamp));
        assertEq(amountRequested, 2 ether);
        assertEq(amountFilled, 1 ether);
        assertEq(amountClaimed, 0 ether);

        // Test the amountPendingAVAX the contract has - should be 0 since 1/2 is partilly filled from receivePrincipalFromMPC
        assertEq(lido.amountPendingAVAX(), 0 ether);

        // User 1 requests another withdrawal
        cheats.prank(USER1_ADDRESS);
        lido.requestWithdrawal(2 ether);

        // Deposit as user 2. This should trigger the filling of the rest of user 1's request.
        cheats.prank(USER2_ADDRESS);
        cheats.deal(USER2_ADDRESS, 1 ether);

        // We expect that the leftover 1 AVAX + the 1 AVAX from the deposit fill user 1's request...
        cheats.expectEmit(true, false, false, true);
        emit RequestFullyFilledEvent(2 ether, uint64(block.timestamp), 0);
        lido.deposit{value: 1 ether}();

        (, , uint256 amountRequested2, uint256 amountFilled2, uint256 amountClaimed2) = lido.unstakeRequests(0);

        assertEq(amountRequested2, 2 ether);
        assertEq(amountFilled2, 2 ether);
        assertEq(amountClaimed2, 0 ether);

        //...and that there is now nothing left pending in the contract.
        assertEq(lido.amountPendingAVAX(), 0 ether);
    }

    // Initiate staking

    function testInitiateStakeZero() public {
        uint256 staked = lido.initiateStake();
        assertEq(staked, 0);
    }

    function testInitiateStakeNoValidators() public {
        cheats.deal(USER1_ADDRESS, 10 ether);
        cheats.prank(USER1_ADDRESS);
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
    //     cheats.deal(USER1_ADDRESS, 10 ether);
    //     cheats.prank(USER1_ADDRESS);
    //     lido.deposit{value: 10 ether}();

    //     validatorSelectMock(validatorSelectorAddress, "test-node", 10 ether, 0);

    //     cheats.expectEmit(true, true, false, true);
    //     emit StakeEvent(10 ether, "test-node", 1800, 1211400);

    //     uint256 staked = lido.initiateStake();
    //     assertEq(staked, 10 ether);
    //     assertEq(address(mpcWalletAddress).balance, 10 ether);
    // }

    function testInitiateStakePartialAllocation() public {
        cheats.deal(USER1_ADDRESS, 10 ether);
        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 10 ether}();

        validatorSelectMock(validatorSelectorAddress, "test-node", 9 ether, 1 ether);
        uint256 staked = lido.initiateStake();
        assertEq(staked, 9 ether);
        assertEq(address(mpcWalletAddress).balance, 9 ether);
        assertEq(lido.amountPendingAVAX(), 1 ether);
    }

    function testInitiateStakeUnderLimit() public {
        cheats.deal(USER1_ADDRESS, 1 ether);
        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 1 ether}();
        uint256 staked = lido.initiateStake();
        assertEq(staked, 0);
        assertEq(lido.amountPendingAVAX(), 1 ether);
    }

    // Unstake Requests

    function testUnstakeRequestZeroAmount() public {
        cheats.expectRevert(AvaLido.InvalidStakeAmount.selector);
        cheats.prank(USER1_ADDRESS);
        lido.requestWithdrawal(0 ether);
    }

    function testTooManyConcurrentUnstakes() public {
        // Deposit as user.
        cheats.startPrank(USER1_ADDRESS);
        cheats.deal(USER1_ADDRESS, 100 ether);
        lido.deposit{value: 100 ether}();
        // Do all the allowed requests
        for (uint256 i = 1; i <= MAXIMUM_UNSTAKE_REQUESTS; i++) {
            lido.requestWithdrawal(1 ether);
        }
        // Try one more
        cheats.expectRevert(AvaLido.TooManyConcurrentUnstakeRequests.selector);
        lido.requestWithdrawal(1 ether);

        cheats.stopPrank();
    }

    function testUnstakeRequest() public {
        // Deposit as user.
        cheats.prank(USER1_ADDRESS);
        cheats.deal(USER1_ADDRESS, 10 ether);
        lido.deposit{value: 10 ether}();

        // Set up validator and stake.
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        assertEq(lido.balanceOf(USER1_ADDRESS), 10 ether);

        // First withdrawal.
        cheats.prank(USER1_ADDRESS);
        uint256 requestId = lido.requestWithdrawal(5 ether);
        assertEq(requestId, 0);
        assertEq(lido.balanceOf(USER1_ADDRESS), 5 ether);

        (
            address requester,
            uint64 requestAt,
            uint256 amountRequested,
            uint256 amountFilled,
            uint256 amountClaimed
        ) = lido.unstakeRequests(requestId);

        assertEq(requester, USER1_ADDRESS);
        assertEq(requestAt, uint64(block.timestamp));
        assertEq(amountRequested, 5 ether);
        assertEq(amountFilled, 0 ether);
        assertEq(amountClaimed, 0 ether);

        // Second withdrawal.
        cheats.prank(USER1_ADDRESS);
        uint256 requestId2 = lido.requestWithdrawal(1 ether);
        (
            address requester2,
            uint256 requestAt2,
            uint256 amountRequested2,
            uint256 amountFilled2,
            uint256 amountClaimed2
        ) = lido.unstakeRequests(requestId2);

        assertEq(requestId2, 1);
        assertEq(lido.balanceOf(USER1_ADDRESS), 4 ether);

        assertEq(requester2, USER1_ADDRESS);
        assertEq(requestAt2, uint64(block.timestamp));
        assertEq(amountRequested2, 1 ether);
        assertEq(amountFilled2, 0 ether);
        assertEq(amountClaimed2, 0 ether);
    }

    function testFillUnstakeRequestSingle() public {
        // Deposit as user.
        cheats.prank(USER1_ADDRESS);
        cheats.deal(USER1_ADDRESS, 10 ether);
        lido.deposit{value: 10 ether}();

        // Set up validator and stake.
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        cheats.prank(USER1_ADDRESS);
        lido.requestWithdrawal(0.5 ether);
        lido.receivePrincipalFromMPC{value: 0.5 ether}();

        (, , uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(0);

        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.5 ether);
    }

    function testMultipleFillUnstakeRequestsSingleFill() public {
        // Deposit as user.
        cheats.deal(USER1_ADDRESS, 10 ether);
        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 10 ether}();

        // Set up validator and stake.
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        // Multiple withdrawal requests as user.
        cheats.startPrank(USER1_ADDRESS);
        lido.requestWithdrawal(0.5 ether);
        lido.requestWithdrawal(0.25 ether);
        lido.requestWithdrawal(0.1 ether);
        cheats.stopPrank();

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
        // Deposit as user.
        cheats.prank(USER1_ADDRESS);
        cheats.deal(USER1_ADDRESS, 10 ether);
        lido.deposit{value: 10 ether}();

        // Set up validator and stake.
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        // Withdraw.
        cheats.prank(USER1_ADDRESS);
        uint256 reqId = lido.requestWithdrawal(0.5 ether);
        lido.receivePrincipalFromMPC{value: 0.1 ether}();

        (, , uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(reqId);

        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.1 ether);
    }

    function testFillUnstakeRequestPartialMultiple() public {
        // Deposit as user.
        cheats.prank(USER1_ADDRESS);
        cheats.deal(USER1_ADDRESS, 10 ether);
        lido.deposit{value: 10 ether}();

        // Set up validator and stake.
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        // Withdraw.
        cheats.prank(USER1_ADDRESS);
        lido.requestWithdrawal(0.5 ether);
        lido.receivePrincipalFromMPC{value: 0.1 ether}();
        lido.receivePrincipalFromMPC{value: 0.1 ether}();

        (, , uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(0);

        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.2 ether);
    }

    function testFillUnstakeRequestPartialMultipleFilled() public {
        // Deposit as user.
        cheats.deal(USER1_ADDRESS, 10 ether);
        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 10 ether}();

        // Check event emission for staking.
        cheats.expectEmit(true, true, false, false);
        emit StakeEvent(10 ether, "test", 1800, 1211400);

        // Set up validator and stake.
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        // Make requests as user.
        cheats.prank(USER1_ADDRESS);
        lido.requestWithdrawal(0.5 ether);

        // Receive principal back from MPC for unstaking.
        lido.receivePrincipalFromMPC{value: 0.1 ether}();

        lido.receivePrincipalFromMPC{value: 0.9 ether}();

        (, , uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(0);

        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.5 ether);
    }

    function testFillUnstakeRequestMultiRequestSingleFill() public {
        // Deposit as user.
        cheats.deal(USER1_ADDRESS, 10 ether);
        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 10 ether}();

        // Set up validator and stake.
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        // Make requests as user.
        cheats.startPrank(USER1_ADDRESS);
        uint256 req1 = lido.requestWithdrawal(0.5 ether);
        uint256 req2 = lido.requestWithdrawal(0.5 ether);
        cheats.stopPrank();

        // Receive principal back from MPC for unstaking.
        lido.receivePrincipalFromMPC{value: 0.5 ether}();

        (, , uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(req1);
        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.5 ether);

        (, , uint256 amountRequested2, uint256 amountFilled2, ) = lido.unstakeRequests(req2);
        assertEq(amountRequested2, 0.5 ether);
        assertEq(amountFilled2, 0);
    }

    function testMultipleRequestReads() public {
        // Deposit as user.
        cheats.deal(USER1_ADDRESS, 10 ether);
        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 10 ether}();

        // Set up validator and stake.
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        cheats.prank(USER1_ADDRESS);
        uint256 reqId = lido.requestWithdrawal(0.5 ether);

        // Make a request as somebody else.
        cheats.deal(USER2_ADDRESS, 0.2 ether);
        cheats.startPrank(USER2_ADDRESS);
        lido.deposit{value: 0.2 ether}();
        lido.requestWithdrawal(0.2 ether);
        cheats.stopPrank();

        // Make another request as the original user.
        cheats.prank(USER1_ADDRESS);
        uint256 reqId2 = lido.requestWithdrawal(0.2 ether);

        assertEq(reqId, 0);
        // Ensure that the next id for the user is the 3rd overall, not second.
        assertEq(reqId2, 2);
    }

    function testUnstakeRequestFillWithFuzzing(uint256 x) public {
        cheats.deal(USER1_ADDRESS, type(uint256).max);
        cheats.assume(x > lido.minStakeBatchAmount());
        cheats.assume(x < MAXIMUM_STAKE_AMOUNT);

        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: x}();

        // Set up validator and stake.
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        cheats.prank(USER1_ADDRESS);
        uint256 requestId = lido.requestWithdrawal(x);
        assertEq(requestId, 0);

        cheats.deal(ZERO_ADDRESS, type(uint256).max);

        cheats.prank(ZERO_ADDRESS);
        lido.receivePrincipalFromMPC{value: x}();

        (, , uint256 amountRequested, uint256 amountFilled, ) = lido.unstakeRequests(0);

        assertEq(amountRequested, x);
        assertEq(amountFilled, x);
    }

    // Claiming

    function testClaimOwnedByOtherUser() public {
        // Deposit as user.
        cheats.deal(USER1_ADDRESS, 10 ether);
        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 10 ether}();

        // Set up validator and stake.
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        // Make request as original user.
        cheats.prank(USER1_ADDRESS);
        uint256 reqId = lido.requestWithdrawal(0.5 ether);

        // Receive principal back from MPC for unstaking.
        lido.receivePrincipalFromMPC{value: 0.5 ether}();

        // Attempt to make a request as somebody else (which should fail).
        cheats.prank(ZERO_ADDRESS);
        cheats.expectRevert(AvaLido.NotAuthorized.selector);
        lido.claim(reqId, 0.5 ether);
    }

    function testClaimTooLarge() public {
        // Deposit as user.
        cheats.deal(USER1_ADDRESS, 10 ether);
        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 10 ether}();

        // Set up validator and stake.
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        // Withdraw as user.
        cheats.prank(USER1_ADDRESS);
        uint256 reqId = lido.requestWithdrawal(0.5 ether);

        // Receive a small amount back from MPC for unstaking.
        lido.receivePrincipalFromMPC{value: 0.5 ether}();

        // Attempt to claim more than we're received.
        cheats.expectRevert(AvaLido.ClaimTooLarge.selector);
        cheats.prank(USER1_ADDRESS);
        lido.claim(reqId, 1 ether);
    }

    function testClaimSucceeds() public {
        // Deposit as user.
        cheats.deal(USER1_ADDRESS, 10 ether);
        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 10 ether}();

        // Set up validator and stake.
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        // No longer has any AVAX, but has stAVAX
        assertEq(address(USER1_ADDRESS).balance, 0);
        assertEq(lido.balanceOf(USER1_ADDRESS), 10 ether);

        // Withdraw as user.
        cheats.prank(USER1_ADDRESS);
        uint256 reqId = lido.requestWithdrawal(4 ether);

        // Some stAVAX is transferred to contract when requesting withdrawal.
        assertEq(lido.balanceOf(USER1_ADDRESS), 6 ether);

        // Receive from MPC for unstaking
        cheats.deal(mpcWalletAddress, 5 ether);
        cheats.prank(mpcWalletAddress);
        lido.receivePrincipalFromMPC{value: 5 ether}();

        assertEq(lido.unstakeRequestCount(USER1_ADDRESS), 1);
        cheats.prank(USER1_ADDRESS);
        lido.claim(reqId, 4 ether);
        assertEq(lido.unstakeRequestCount(USER1_ADDRESS), 0);

        // Has the AVAX they claimed back.
        assertEq(address(USER1_ADDRESS).balance, 4 ether);

        // Still has remaming stAVAX
        assertEq(lido.balanceOf(USER1_ADDRESS), 6 ether);

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

        assertEq(lido.unstakeRequestCount(DEPLOYER_ADDRESS), 1);
        lido.claim(reqId, 0.5 ether);

        // Request should still be there.
        assertEq(lido.unstakeRequestCount(DEPLOYER_ADDRESS), 1);

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

        assertEq(lido.unstakeRequestCount(DEPLOYER_ADDRESS), 1);
        lido.claim(reqId, 0.5 ether);

        // Request should still be there.
        assertEq(lido.unstakeRequestCount(DEPLOYER_ADDRESS), 1);

        (, , uint256 amountRequested, uint256 amountFilled, uint256 amountClaimed) = lido.unstakeRequests(reqId);

        assertEq(amountRequested, 1 ether);
        assertEq(amountFilled, 1 ether);
        assertEq(amountClaimed, 0.5 ether);

        lido.claim(reqId, 0.25 ether);

        (, , , , uint256 amountClaimed2) = lido.unstakeRequests(reqId);
        assertEq(amountClaimed2, 0.75 ether);

        lido.claim(reqId, 0.25 ether);
        assertEq(lido.unstakeRequestCount(DEPLOYER_ADDRESS), 0);

        (address requester, , , , ) = lido.unstakeRequests(reqId);

        // Full claim so expect the data to be removed.
        assertEq(requester, ZERO_ADDRESS);
    }

    function testClaimWithFuzzing(uint256 x) public {
        cheats.deal(DEPLOYER_ADDRESS, type(uint256).max);

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
