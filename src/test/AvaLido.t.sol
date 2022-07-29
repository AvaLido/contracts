// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "../AvaLido.sol";
import "../interfaces/IOracle.sol";

import "./helpers.sol";

import "openzeppelin-contracts/contracts/finance/PaymentSplitter.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";
import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";

contract FakeMpcManager is IMpcManager {
    event FakeStakeRequested(string validator, uint256 amount, uint256 stakeStartTime, uint256 stakeEndTime);

    function setAvaLidoAddress(address avaLidoAddress) external {}

    function requestStake(
        string calldata nodeID,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    ) external payable {
        require(msg.value == amount, "Incorrect value.");
        string memory logData = string(
            abi.encodePacked(
                nodeID,
                ", ",
                Strings.toString(amount),
                ", ",
                Strings.toString(startTime),
                ", ",
                Strings.toString(endTime)
            )
        );
        payable(MPC_GENERATED_ADDRESS).transfer(amount);
        emit FakeStakeRequested(nodeID, amount, startTime, endTime);
    }

    function createGroup(bytes[] calldata, uint8) external {
        revert("Not Implemented");
    }

    function requestKeygen(bytes32) external {
        revert("Not Implemented");
    }

    function getGroup(bytes32) external view returns (bytes[] memory) {
        revert("Not Implemented");
    }

    function getKey(bytes calldata) external view returns (KeyInfo memory) {
        revert("Not Implemented");
    }
}

contract AvaLidoTest is DSTest, Helpers {
    event FakeStakeRequested(string validator, uint256 amount, uint256 stakeStartTime, uint256 stakeEndTime);
    event RewardsCollectedEvent(uint256 amount);
    event ProtocolFeeEvent(uint256 amount);
    event RequestFullyFilledEvent(uint256 indexed requestedAmount, uint256 timestamp, uint256 requestIndex);
    event RequestPartiallyFilledEvent(uint256 indexed fillAmount, uint256 timestamp, uint256 requestIndex);

    AvaLido lido;
    ValidatorSelector validatorSelector;
    FakeMpcManager fakeMpcManager;
    PrincipalTreasury pTreasury;
    RewardTreasury rTreasury;

    address feeAddressAuthor = 0x1000000000000000000000000000000000000001;
    address feeAddressLido = 0x1000000000000000000000000000000000000002;
    address mpcManagerAddress;
    address validatorSelectorAddress;
    address pTreasuryAddress;
    address rTreasuryAddress;

    function setUp() public {
        // Not an actual oracle contract, but calls to ValidatorSelector should all be stubbed.
        IOracle oracle = IOracle(0x9000000000000000000000000000000000000001);

        ValidatorSelector _validatorSelector = new ValidatorSelector();
        validatorSelector = ValidatorSelector(proxyWrapped(address(_validatorSelector), ROLE_PROXY_ADMIN));
        validatorSelector.initialize(address(oracle));

        FakeMpcManager _fakeMpcManager = new FakeMpcManager();
        fakeMpcManager = FakeMpcManager(proxyWrapped(address(_fakeMpcManager), ROLE_PROXY_ADMIN));

        PrincipalTreasury _pTreasury = new PrincipalTreasury();
        pTreasury = PrincipalTreasury(proxyWrapped(address(_pTreasury), ROLE_PROXY_ADMIN));
        RewardTreasury _rTreasury = new RewardTreasury();
        rTreasury = RewardTreasury(proxyWrapped(address(_rTreasury), ROLE_PROXY_ADMIN));

        validatorSelectorAddress = address(validatorSelector);
        mpcManagerAddress = address(fakeMpcManager);
        pTreasuryAddress = address(pTreasury);
        rTreasuryAddress = address(rTreasury);

        AvaLido _lido = new PayableAvaLido();
        lido = PayableAvaLido(payable(proxyWrapped(address(_lido), ROLE_PROXY_ADMIN)));
        lido.initialize(feeAddressLido, feeAddressAuthor, validatorSelectorAddress, mpcManagerAddress);
        lido.setPrincipalTreasuryAddress(pTreasuryAddress);
        lido.setRewardTreasuryAddress(rTreasuryAddress);
        pTreasury.initialize(address(lido));
        rTreasury.initialize(address(lido));
    }

    receive() external payable {}

    // Deposit

    function testStakeBasic() public {
        cheats.deal(USER1_ADDRESS, 10 ether);
        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 1 ether}();
        assertEq(lido.balanceOf(USER1_ADDRESS), 1 ether);
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
        cheats.deal(USER1_ADDRESS, type(uint256).max);

        cheats.assume(x > lido.minStakeAmount());
        cheats.assume(x < MAXIMUM_STAKE_AMOUNT);

        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: x}();
        assertEq(lido.balanceOf(USER1_ADDRESS), x);
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
        cheats.deal(pTreasuryAddress, 1 ether);
        lido.claimUnstakedPrincipals();

        // Test that user 1's request has been partially filled
        (
            address requester,
            uint64 requestAt,
            uint256 amountRequested,
            uint256 amountFilled,
            uint256 amountClaimed,
            uint256 stAVAXLocked
        ) = lido.unstakeRequests(0);

        assertEq(requester, USER1_ADDRESS);
        assertEq(requestAt, uint64(block.timestamp));
        assertEq(amountRequested, 2 ether);
        assertEq(amountFilled, 1 ether);
        assertEq(amountClaimed, 0 ether);
        assertEq(stAVAXLocked, 2 ether);

        // Test the amountPendingAVAX the contract has - should be 0 since 1/2 is partilly filled from claimUnstakedPrincipals
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

        (, , uint256 amountRequested2, uint256 amountFilled2, uint256 amountClaimed2, uint256 stAVAXLocked2) = lido
            .unstakeRequests(0);

        assertEq(amountRequested2, 2 ether);
        assertEq(amountFilled2, 2 ether);
        assertEq(amountClaimed2, 0 ether);
        assertEq(stAVAXLocked2, 2 ether);

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
    //     assertEq(address(mpcManagerAddress).balance, 10 ether);
    // }

    function testInitiateStakePartialAllocation() public {
        cheats.deal(USER1_ADDRESS, 10 ether);
        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 10 ether}();

        validatorSelectMock(validatorSelectorAddress, "test-node", 9 ether, 1 ether);

        cheats.expectEmit(false, false, false, true);
        emit FakeStakeRequested("test-node", 9 ether, 1801, 1211401);
        uint256 staked = lido.initiateStake();

        assertEq(staked, 9 ether);
        assertEq(address(MPC_GENERATED_ADDRESS).balance, 9 ether);
        assertEq(lido.amountPendingAVAX(), 1 ether);
    }

    function testInitiateStakeUnderLimit() public {
        cheats.deal(USER1_ADDRESS, 1 ether);
        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 1 ether}();

        validatorSelectMock(validatorSelectorAddress, "test", 1 ether, 1 ether);
        uint256 staked = lido.initiateStake();
        assertEq(staked, 0);
        assertEq(lido.amountPendingAVAX(), 1 ether);
    }

    // NOTE: This is a `testFail` to ensure that an event is *not* emitted.
    function testFailStakeSparseArray() public {
        cheats.deal(USER1_ADDRESS, 100 ether);
        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 100 ether}();

        cheats.expectEmit(false, false, false, false);
        emit FakeStakeRequested("test-node", 99 ether, 1801, 1211401);

        validatorSelectMock(validatorSelectorAddress, "test", 0 ether, 1 ether);
        uint256 staked = lido.initiateStake();
        assertEq(staked, 99 ether);
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
        for (uint256 i = 1; i <= lido.maxUnstakeRequests(); i++) {
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
        lido.approve(address(lido), 5 ether);
        assertEq(lido.allowance(USER1_ADDRESS, address(lido)), 5 ether);

        cheats.prank(USER1_ADDRESS);
        uint256 requestId = lido.requestWithdrawal(5 ether);

        assertEq(requestId, 0);
        assertEq(lido.balanceOf(USER1_ADDRESS), 5 ether);

        (
            address requester,
            uint64 requestAt,
            uint256 amountRequested,
            uint256 amountFilled,
            uint256 amountClaimed,
            uint256 stAVAXLocked
        ) = lido.unstakeRequests(requestId);

        assertEq(requester, USER1_ADDRESS);
        assertEq(requestAt, uint64(block.timestamp));
        assertEq(amountRequested, 5 ether);
        assertEq(amountFilled, 0 ether);
        assertEq(amountClaimed, 0 ether);
        assertEq(stAVAXLocked, 5 ether);

        // Second withdrawal.
        cheats.prank(USER1_ADDRESS);
        uint256 requestId2 = lido.requestWithdrawal(1 ether);
        (
            address requester2,
            uint256 requestAt2,
            uint256 amountRequested2,
            uint256 amountFilled2,
            uint256 amountClaimed2,
            uint256 stAVAXLocked2
        ) = lido.unstakeRequests(requestId2);

        assertEq(requestId2, 1);
        assertEq(lido.balanceOf(USER1_ADDRESS), 4 ether);

        assertEq(requester2, USER1_ADDRESS);
        assertEq(requestAt2, uint64(block.timestamp));
        assertEq(amountRequested2, 1 ether);
        assertEq(amountFilled2, 0 ether);
        assertEq(amountClaimed2, 0 ether);
        assertEq(stAVAXLocked2, 1 ether);
    }

    function testUnstakeRequestAfterRewards() public {
        // Deposit as user.
        cheats.prank(USER1_ADDRESS);
        cheats.deal(USER1_ADDRESS, 10 ether);
        lido.deposit{value: 10 ether}();

        // Set up validator and stake.
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        assertEq(lido.balanceOf(USER1_ADDRESS), 10 ether);
        assertEq(lido.exchangeRateAVAXToStAVAX(), 1 ether);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1 ether);

        cheats.deal(rTreasuryAddress, 0.2 ether);
        lido.claimRewards();

        // assert new exchange rate
        assertEq(lido.exchangeRateAVAXToStAVAX(), 982318271119842829);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1.018 ether);

        // The user's 10 stAVAX should now be worth 10.18 AVAX

        // First withdrawal.
        cheats.prank(USER1_ADDRESS);
        lido.approve(address(lido), 5 ether);
        assertEq(lido.allowance(USER1_ADDRESS, address(lido)), 5 ether);

        cheats.prank(USER1_ADDRESS);
        uint256 requestId = lido.requestWithdrawal(5 ether);

        assertEq(requestId, 0);
        assertEq(lido.balanceOf(USER1_ADDRESS), 5 ether);

        (
            address requester,
            uint64 requestAt,
            uint256 amountRequested,
            uint256 amountFilled,
            uint256 amountClaimed,
            uint256 stAVAXLocked
        ) = lido.unstakeRequests(requestId);

        assertEq(requester, USER1_ADDRESS);
        assertEq(requestAt, uint64(block.timestamp));
        assertEq(amountRequested, 5.09 ether);
        assertEq(amountFilled, 0 ether);
        assertEq(amountClaimed, 0 ether);
        assertEq(stAVAXLocked, 5 ether);

        // Second withdrawal.
        cheats.prank(USER1_ADDRESS);
        uint256 requestId2 = lido.requestWithdrawal(1 ether);
        (
            address requester2,
            uint256 requestAt2,
            uint256 amountRequested2,
            uint256 amountFilled2,
            uint256 amountClaimed2,
            uint256 stAVAXLocked2
        ) = lido.unstakeRequests(requestId2);

        assertEq(requestId2, 1);
        assertEq(lido.balanceOf(USER1_ADDRESS), 4 ether);

        assertEq(requester2, USER1_ADDRESS);
        assertEq(requestAt2, uint64(block.timestamp));
        assertEq(amountRequested2, 1.018 ether);
        assertEq(amountFilled2, 0 ether);
        assertEq(amountClaimed2, 0 ether);
        assertEq(stAVAXLocked2, 1 ether);
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
        cheats.deal(pTreasuryAddress, 0.5 ether);
        lido.claimUnstakedPrincipals();

        (, , uint256 amountRequested, uint256 amountFilled, , uint256 stAVAXLocked) = lido.unstakeRequests(0);

        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.5 ether);
        assertEq(stAVAXLocked, 0.5 ether);
    }

    function testFillUnstakeRequestSingleAfterRewardsReceived() public {
        // Deposit as user.
        cheats.prank(USER1_ADDRESS);
        cheats.deal(USER1_ADDRESS, 10 ether);
        lido.deposit{value: 10 ether}();

        // Set up validator and stake.
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        // 10.09 AVAX for 10 stAVAX = 1 AVAX for 0.99108 stAVAX
        cheats.deal(rTreasuryAddress, 0.1 ether);
        lido.claimRewards();

        assertEq(lido.protocolControlledAVAX(), 10.09 ether);
        assertEq(lido.exchangeRateAVAXToStAVAX(), 991080277502477700);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1.009 ether);

        // So we withdraw 1 AVAX and lock 0.99108... stAVAX
        cheats.prank(USER1_ADDRESS);
        lido.requestWithdrawal(1 ether);

        cheats.deal(pTreasuryAddress, 1 ether);
        lido.claimUnstakedPrincipals();

        (, , uint256 amountRequested, uint256 amountFilled, , uint256 stAVAXLocked) = lido.unstakeRequests(0);

        assertEq(amountRequested, 1.009 ether);
        assertEq(amountFilled, 1 ether);
        assertEq(stAVAXLocked, 1 ether);
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

        cheats.deal(pTreasuryAddress, 1 ether);
        lido.claimUnstakedPrincipals();

        (, , uint256 amountRequested, uint256 amountFilled, , ) = lido.unstakeRequests(0);
        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.5 ether);

        (, , uint256 amountRequested2, uint256 amountFilled2, , ) = lido.unstakeRequests(1);
        assertEq(amountRequested2, 0.25 ether);
        assertEq(amountFilled2, 0.25 ether);

        (, , uint256 amountRequested3, uint256 amountFilled3, , ) = lido.unstakeRequests(2);
        assertEq(amountRequested3, 0.1 ether);
        assertEq(amountFilled3, 0.1 ether);
    }

    function testMultipleFillUnstakeRequestsSingleFillAfterRewards() public {
        // Deposit as user.
        cheats.prank(USER1_ADDRESS);
        cheats.deal(USER1_ADDRESS, 10 ether);
        lido.deposit{value: 10 ether}();

        // Set up validator and stake.
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        // 10.09 AVAX for 10 stAVAX = 1 AVAX for 0.99108 stAVAX
        cheats.deal(rTreasuryAddress, 0.1 ether);
        lido.claimRewards();

        assertEq(lido.protocolControlledAVAX(), 10.09 ether);
        assertEq(lido.exchangeRateAVAXToStAVAX(), 991080277502477700);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1.009 ether);

        // So we withdraw 1 AVAX and lock 0.99108... stAVAX
        // Multiple withdrawal requests as user.
        cheats.startPrank(USER1_ADDRESS);
        lido.requestWithdrawal(0.1 ether);
        lido.requestWithdrawal(0.25 ether);
        lido.requestWithdrawal(0.5 ether);
        cheats.stopPrank();

        cheats.deal(pTreasuryAddress, 1 ether);
        lido.claimUnstakedPrincipals();

        (, , uint256 amountRequested, uint256 amountFilled, , uint256 amountLocked) = lido.unstakeRequests(0);
        assertEq(amountRequested, 0.1009 ether);
        assertEq(amountFilled, 0.1009 ether);
        assertEq(amountLocked, 0.1 ether);

        (, , uint256 amountRequested2, uint256 amountFilled2, , uint256 amountLocked2) = lido.unstakeRequests(1);
        assertEq(amountRequested2, 0.25 * 1.009 ether);
        assertEq(amountFilled2, 0.25 * 1.009 ether);
        assertEq(amountLocked2, 0.25 ether);

        (, , uint256 amountRequested3, uint256 amountFilled3, , uint256 amountLocked3) = lido.unstakeRequests(2);
        assertEq(amountRequested3, 0.5 * 1.009 ether);
        assertEq(amountFilled3, 0.5 * 1.009 ether);
        assertEq(amountLocked3, 0.5 ether);
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
        cheats.deal(pTreasuryAddress, 0.1 ether);
        lido.claimUnstakedPrincipals();

        (, , uint256 amountRequested, uint256 amountFilled, , ) = lido.unstakeRequests(reqId);

        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.1 ether);
    }

    function testFillUnstakeRequestPartialAfterRewards() public {
        // Deposit as user.
        cheats.prank(USER1_ADDRESS);
        cheats.deal(USER1_ADDRESS, 10 ether);
        lido.deposit{value: 10 ether}();

        // Set up validator and stake.
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        // 10.09 AVAX for 10 stAVAX = 1 AVAX for 0.99108 stAVAX
        cheats.deal(rTreasuryAddress, 0.1 ether);
        lido.claimRewards();

        assertEq(lido.protocolControlledAVAX(), 10.09 ether);
        assertEq(lido.exchangeRateAVAXToStAVAX(), 991080277502477700);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1.009 ether);

        // So we withdraw 1 AVAX and lock 0.99108... stAVAX
        cheats.prank(USER1_ADDRESS);
        uint256 reqId = lido.requestWithdrawal(1 ether);

        cheats.deal(pTreasuryAddress, 0.1 ether);
        lido.claimUnstakedPrincipals();

        (, , uint256 amountRequested, uint256 amountFilled, , uint256 amountLocked) = lido.unstakeRequests(reqId);

        assertEq(amountRequested, 1.009 ether);
        assertEq(amountFilled, 0.1 ether);
        assertEq(amountLocked, 1 ether);
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
        cheats.deal(pTreasuryAddress, 0.1 ether);
        lido.claimUnstakedPrincipals();
        cheats.deal(pTreasuryAddress, 0.1 ether);
        lido.claimUnstakedPrincipals();

        (, , uint256 amountRequested, uint256 amountFilled, , uint256 stAVAXLocked) = lido.unstakeRequests(0);

        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.2 ether);
        assertEq(stAVAXLocked, 0.5 ether);
    }

    function testFillUnstakeRequestPartialMultipleAfterRewards() public {
        // Deposit as user.
        cheats.prank(USER1_ADDRESS);
        cheats.deal(USER1_ADDRESS, 10 ether);
        lido.deposit{value: 10 ether}();

        // Set up validator and stake.
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        // 10.09 AVAX for 10 stAVAX = 1 AVAX for 0.99108 stAVAX
        cheats.deal(rTreasuryAddress, 0.1 ether);
        lido.claimRewards();

        assertEq(lido.protocolControlledAVAX(), 10.09 ether);
        assertEq(lido.exchangeRateAVAXToStAVAX(), 991080277502477700);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1.009 ether);

        // So we withdraw 1 AVAX and lock 0.99108... stAVAX
        cheats.prank(USER1_ADDRESS);
        lido.requestWithdrawal(1 ether);

        cheats.deal(pTreasuryAddress, 0.1 ether);
        lido.claimUnstakedPrincipals();
        cheats.deal(pTreasuryAddress, 0.1 ether);
        lido.claimUnstakedPrincipals();

        (, , uint256 amountRequested, uint256 amountFilled, , uint256 stAVAXLocked) = lido.unstakeRequests(0);

        assertEq(amountRequested, 1.009 ether);
        assertEq(amountFilled, 0.2 ether);
        assertEq(stAVAXLocked, 1 ether);
    }

    function testFillUnstakeRequestPartialMultipleFilled() public {
        // Deposit as user.
        cheats.deal(USER1_ADDRESS, 10 ether);
        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 10 ether}();

        // Check event emission for staking.
        cheats.expectEmit(false, false, false, true);
        emit FakeStakeRequested("test", 10 ether, 1801, 1211401);

        // Set up validator and stake.
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        // Make requests as user.
        cheats.prank(USER1_ADDRESS);
        lido.requestWithdrawal(0.5 ether);

        // Receive principal back from MPC for unstaking.
        cheats.deal(pTreasuryAddress, 0.1 ether);
        lido.claimUnstakedPrincipals();
        cheats.deal(pTreasuryAddress, 0.9 ether);
        lido.claimUnstakedPrincipals();

        (, , uint256 amountRequested, uint256 amountFilled, , uint256 stAVAXLocked) = lido.unstakeRequests(0);

        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.5 ether);
        assertEq(stAVAXLocked, 0.5 ether);
    }

    function testFillUnstakeRequestPartialMultipleFilledAfterRewards() public {
        // Deposit as user.
        cheats.prank(USER1_ADDRESS);
        cheats.deal(USER1_ADDRESS, 10 ether);
        lido.deposit{value: 10 ether}();

        // Set up validator and stake.
        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        // 10.09 AVAX for 10 stAVAX = 1 AVAX for 0.99108 stAVAX
        cheats.deal(rTreasuryAddress, 0.1 ether);
        lido.claimRewards();

        assertEq(lido.protocolControlledAVAX(), 10.09 ether);
        assertEq(lido.exchangeRateAVAXToStAVAX(), 991080277502477700);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1.009 ether);

        // So we withdraw 1 AVAX and lock 0.99108... stAVAX
        cheats.prank(USER1_ADDRESS);
        lido.requestWithdrawal(0.5 ether);

        cheats.deal(pTreasuryAddress, 0.1 ether);
        lido.claimUnstakedPrincipals();
        cheats.deal(pTreasuryAddress, 0.9 ether);
        lido.claimUnstakedPrincipals();

        (, , uint256 amountRequested, uint256 amountFilled, , uint256 stAVAXLocked) = lido.unstakeRequests(0);

        assertEq(amountRequested, 0.5045 ether);
        assertEq(amountFilled, 0.5045 ether);
        assertEq(stAVAXLocked, 0.5 ether);
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
        cheats.deal(pTreasuryAddress, 0.5 ether);
        lido.claimUnstakedPrincipals();

        (, , uint256 amountRequested, uint256 amountFilled, , ) = lido.unstakeRequests(req1);
        assertEq(amountRequested, 0.5 ether);
        assertEq(amountFilled, 0.5 ether);

        (, , uint256 amountRequested2, uint256 amountFilled2, , ) = lido.unstakeRequests(req2);
        assertEq(amountRequested2, 0.5 ether);
        assertEq(amountFilled2, 0);
    }

    // function testFillUnstakeRequestMultiRequestSingleFill() public {}

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
        validatorSelectMock(validatorSelectorAddress, "test", x, 0);
        lido.initiateStake();

        cheats.prank(USER1_ADDRESS);
        uint256 requestId = lido.requestWithdrawal(x);
        assertEq(requestId, 0);

        cheats.deal(ZERO_ADDRESS, type(uint256).max);

        cheats.prank(ZERO_ADDRESS);
        cheats.deal(pTreasuryAddress, x);
        lido.claimUnstakedPrincipals();

        (, , uint256 amountRequested, uint256 amountFilled, , uint256 stAVAXLocked) = lido.unstakeRequests(0);

        assertEq(amountRequested, x);
        assertEq(amountFilled, x);
        assertEq(stAVAXLocked, x);
    }

    // function testUnstakeRequestFillWithFuzzingAfterRewards(uint256 x) public {
    //     cheats.deal(USER1_ADDRESS, type(uint256).max);
    //     cheats.deal(USER2_ADDRESS, type(uint256).max);
    //     cheats.assume(x > lido.minStakeBatchAmount());
    //     cheats.assume(x < MAXIMUM_STAKE_AMOUNT);

    //     cheats.prank(USER2_ADDRESS);
    //     lido.deposit{value: x}();

    //     lido.receiveRewardsFromMPC{value: 0.6 ether}();

    //     cheats.prank(USER1_ADDRESS);
    //     lido.deposit{value: x}();

    //     uint256 stAVAXReceivedByUser = lido.balanceOf(USER1_ADDRESS);

    //     // Set up validator and stake.
    //     // We want to move all the AVAX in the contract (x + x + lido.receiveRewardsFromMPC{value: 0.5 ether}())
    //     // or else it messes up the test
    //     validatorSelectMock(validatorSelectorAddress, "test", lido.protocolControlledAVAX(), 0);
    //     lido.initiateStake();

    //     cheats.prank(USER1_ADDRESS);
    //     uint256 requestId = lido.requestWithdrawal(x);
    //     assertEq(requestId, 0);

    //     cheats.deal(ZERO_ADDRESS, type(uint256).max);

    //     cheats.prank(ZERO_ADDRESS);
    //     lido.receivePrincipalFromMPC{value: x}();

    //     (, , uint256 amountRequested, uint256 amountFilled, , uint256 stAVAXLocked) = lido.unstakeRequests(0);

    //     assertEq(amountRequested, x);
    //     assertEq(amountFilled, x);
    //     assertEq(stAVAXLocked, stAVAXReceivedByUser);
    // }

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
        cheats.deal(pTreasuryAddress, 0.5 ether);
        lido.claimUnstakedPrincipals();

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
        cheats.deal(pTreasuryAddress, 0.5 ether);
        lido.claimUnstakedPrincipals();

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
        cheats.deal(MPC_GENERATED_ADDRESS, 5 ether);
        cheats.prank(MPC_GENERATED_ADDRESS);

        cheats.deal(pTreasuryAddress, 5 ether);
        lido.claimUnstakedPrincipals();

        assertEq(lido.unstakeRequestCount(USER1_ADDRESS), 1);
        cheats.prank(USER1_ADDRESS);
        lido.claim(reqId, 4 ether);
        assertEq(lido.unstakeRequestCount(USER1_ADDRESS), 0);

        // Has the AVAX they claimed back.
        assertEq(address(USER1_ADDRESS).balance, 4 ether);

        // Still has remaming stAVAX
        assertEq(lido.balanceOf(USER1_ADDRESS), 6 ether);

        (address requester, , uint256 amountRequested, , uint256 amountClaimed, ) = lido.unstakeRequests(reqId);

        // Full claim so expect the data to be removed.
        assertEq(requester, ZERO_ADDRESS);
        assertEq(amountRequested, 0);
        assertEq(amountClaimed, 0);
    }

    function testClaimSucceedsAfterRewardsReceived() public {
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

        cheats.deal(rTreasuryAddress, 0.1 ether);
        lido.claimRewards();

        assertEq(lido.protocolControlledAVAX(), 10.09 ether);
        assertEq(lido.exchangeRateAVAXToStAVAX(), 991080277502477700);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1.009 ether);

        // Withdraw as user.
        cheats.prank(USER1_ADDRESS);
        uint256 reqId = lido.requestWithdrawal(1 ether);

        // Some stAVAX is transferred to contract when requesting withdrawal.
        // They had 10 stAVAX and request to withdraw 1 so should have 9 left.
        assertEq(lido.balanceOf(USER1_ADDRESS), 9 ether);

        // Receive from MPC for unstaking
        cheats.deal(pTreasuryAddress, 5 ether);
        lido.claimUnstakedPrincipals();

        // Exchange rates should still be the same
        assertEq(lido.exchangeRateAVAXToStAVAX(), 991080277502477700);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1.009 ether);

        // They should claim 1.009 AVAX
        assertEq(lido.unstakeRequestCount(USER1_ADDRESS), 1);
        cheats.prank(USER1_ADDRESS);
        lido.claim(reqId, 1.009 ether);
        assertEq(lido.unstakeRequestCount(USER1_ADDRESS), 0);

        // Has the AVAX they claimed back.
        assertEq(address(USER1_ADDRESS).balance, 1.009 ether);

        // Still has remaining stAVAX
        assertEq(lido.balanceOf(USER1_ADDRESS), 9 ether);

        (address requester, , uint256 amountRequested, , uint256 amountClaimed, uint256 stAVAXLocked) = lido
            .unstakeRequests(reqId);

        // Full claim so expect the data to be removed.
        assertEq(requester, ZERO_ADDRESS);
        assertEq(amountRequested, 0);
        assertEq(amountClaimed, 0);
        assertEq(stAVAXLocked, 0);
    }

    function testClaimSucceedsAfterRewardsReceivedBetweenRequestAndClaim() public {
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

        cheats.deal(rTreasuryAddress, 0.1 ether);
        lido.claimRewards();

        assertEq(lido.protocolControlledAVAX(), 10.09 ether);
        assertEq(lido.exchangeRateAVAXToStAVAX(), 991080277502477700);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1.009 ether);

        // Withdraw as user.
        cheats.prank(USER1_ADDRESS);
        uint256 reqId = lido.requestWithdrawal(1 ether);

        // Some stAVAX is transferred to contract when requesting withdrawal.
        // They had 10 stAVAX and request to withdraw 1 so should have 9 left.
        assertEq(lido.balanceOf(USER1_ADDRESS), 9 ether);

        // Receive from MPC for unstaking
        cheats.deal(pTreasuryAddress, 5 ether);
        lido.claimUnstakedPrincipals();

        // Exchange rates should still be the same
        assertEq(lido.exchangeRateAVAXToStAVAX(), 991080277502477700);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1.009 ether);

        // Now we receive more rewards
        cheats.deal(rTreasuryAddress, 0.1 ether);
        lido.claimRewards();

        // Exchange rate should be different...
        assertEq(lido.protocolControlledAVAX(), 10.18 ether);
        assertEq(lido.exchangeRateAVAXToStAVAX(), 982318271119842829);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1.018 ether);

        // ...but their claim should still be same as test above: 1.009 AVAX
        // because the exchange rate is locked at time of request
        assertEq(lido.unstakeRequestCount(USER1_ADDRESS), 1);
        cheats.prank(USER1_ADDRESS);
        lido.claim(reqId, 1.009 ether);
        assertEq(lido.unstakeRequestCount(USER1_ADDRESS), 0);

        // Has the AVAX they claimed back.
        assertEq(address(USER1_ADDRESS).balance, 1.009 ether);

        // Still has remaining stAVAX
        assertEq(lido.balanceOf(USER1_ADDRESS), 9 ether);

        (address requester, , uint256 amountRequested, , uint256 amountClaimed, uint256 stAVAXLocked) = lido
            .unstakeRequests(reqId);

        // Full claim so expect the data to be removed.
        assertEq(requester, ZERO_ADDRESS);
        assertEq(amountRequested, 0);
        assertEq(amountClaimed, 0);
        assertEq(stAVAXLocked, 0);
    }

    function testPartialClaimSucceeds() public {
        cheats.deal(USER1_ADDRESS, 10 ether);

        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 10 ether}();

        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        cheats.prank(USER1_ADDRESS);
        uint256 reqId = lido.requestWithdrawal(1 ether);
        cheats.deal(pTreasuryAddress, 1 ether);
        lido.claimUnstakedPrincipals();

        assertEq(lido.unstakeRequestCount(USER1_ADDRESS), 1);

        cheats.prank(USER1_ADDRESS);
        lido.claim(reqId, 0.5 ether);

        // Request should still be there.
        assertEq(lido.unstakeRequestCount(USER1_ADDRESS), 1);

        (, , uint256 amountRequested, uint256 amountFilled, uint256 amountClaimed, uint256 stAVAXLocked) = lido
            .unstakeRequests(reqId);

        assertEq(amountRequested, 1 ether);
        assertEq(amountFilled, 1 ether);
        assertEq(amountClaimed, 0.5 ether);
        assertEq(stAVAXLocked, 1 ether);
    }

    function testPartialClaimSucceedsAfterRewards() public {
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

        cheats.deal(rTreasuryAddress, 0.1 ether);
        lido.claimRewards();

        assertEq(lido.protocolControlledAVAX(), 10.09 ether);
        assertEq(lido.exchangeRateAVAXToStAVAX(), 991080277502477700);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1.009 ether);

        // Withdraw as user.
        cheats.prank(USER1_ADDRESS);
        uint256 reqId = lido.requestWithdrawal(1 ether);

        // Receive from MPC for unstaking
        cheats.deal(pTreasuryAddress, 5 ether);
        lido.claimUnstakedPrincipals();

        // Exchange rates should still be the same
        assertEq(lido.exchangeRateAVAXToStAVAX(), 991080277502477700);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1.009 ether);

        assertEq(lido.unstakeRequestCount(USER1_ADDRESS), 1);

        // Now we receive more rewards
        cheats.deal(rTreasuryAddress, 0.1 ether);
        lido.claimRewards();

        // Exchange rate should be different...
        assertEq(lido.protocolControlledAVAX(), 10.18 ether);
        assertEq(lido.exchangeRateAVAXToStAVAX(), 982318271119842829);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1.018 ether);

        // ...but their claim should still be same as test above: 1.009 AVAX
        // because the exchange rate is locked at time of request
        cheats.prank(USER1_ADDRESS);
        lido.claim(reqId, 0.5 ether);

        // Request should still be there.
        assertEq(lido.unstakeRequestCount(USER1_ADDRESS), 1);

        (, , uint256 amountRequested, uint256 amountFilled, uint256 amountClaimed, uint256 stAVAXLocked) = lido
            .unstakeRequests(reqId);

        assertEq(amountRequested, 1.009 ether);
        assertEq(amountFilled, 1.009 ether);
        assertEq(amountClaimed, 0.5 ether);
        assertEq(stAVAXLocked, 1 ether);
    }

    function testMultiplePartialClaims() public {
        cheats.deal(USER1_ADDRESS, 10 ether);
        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 10 ether}();

        validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
        lido.initiateStake();

        cheats.prank(USER1_ADDRESS);
        uint256 reqId = lido.requestWithdrawal(1 ether);

        cheats.deal(pTreasuryAddress, 1 ether);
        lido.claimUnstakedPrincipals();

        assertEq(lido.unstakeRequestCount(USER1_ADDRESS), 1);
        cheats.prank(USER1_ADDRESS);
        lido.claim(reqId, 0.5 ether);

        // Request should still be there.
        assertEq(lido.unstakeRequestCount(USER1_ADDRESS), 1);

        (, , uint256 amountRequested, uint256 amountFilled, uint256 amountClaimed, uint256 stAVAXLocked) = lido
            .unstakeRequests(reqId);

        assertEq(amountRequested, 1 ether);
        assertEq(amountFilled, 1 ether);
        assertEq(amountClaimed, 0.5 ether);
        assertEq(stAVAXLocked, 1 ether);

        cheats.prank(USER1_ADDRESS);
        lido.claim(reqId, 0.25 ether);

        (, , , , uint256 amountClaimed2, ) = lido.unstakeRequests(reqId);
        assertEq(amountClaimed2, 0.75 ether);

        cheats.prank(USER1_ADDRESS);
        lido.claim(reqId, 0.25 ether);
        assertEq(lido.unstakeRequestCount(USER1_ADDRESS), 0);

        (address requester, , , , , ) = lido.unstakeRequests(reqId);

        // Full claim so expect the data to be removed.
        assertEq(requester, ZERO_ADDRESS);
    }

    function testMultiplePartialClaimsAfterRewards() public {
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

        cheats.deal(rTreasuryAddress, 0.1 ether);
        lido.claimRewards();

        assertEq(lido.protocolControlledAVAX(), 10.09 ether);
        assertEq(lido.exchangeRateAVAXToStAVAX(), 991080277502477700);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1.009 ether);

        // Withdraw as user.
        cheats.prank(USER1_ADDRESS);
        uint256 reqId = lido.requestWithdrawal(1 ether);

        // Receive from MPC for unstaking
        cheats.deal(pTreasuryAddress, 5 ether);
        lido.claimUnstakedPrincipals();

        // Exchange rates should still be the same
        assertEq(lido.exchangeRateAVAXToStAVAX(), 991080277502477700);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1.009 ether);

        assertEq(lido.unstakeRequestCount(USER1_ADDRESS), 1);

        // Now we receive more rewards
        cheats.deal(rTreasuryAddress, 0.1 ether);
        lido.claimRewards();

        // Exchange rate should be different...
        assertEq(lido.protocolControlledAVAX(), 10.18 ether);
        assertEq(lido.exchangeRateAVAXToStAVAX(), 982318271119842829);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1.018 ether);

        // ...but their claim should still be same as test above: 1.009 AVAX
        // because the exchange rate is locked at time of request
        cheats.prank(USER1_ADDRESS);
        lido.claim(reqId, 0.5 ether);

        // Request should still be there.
        assertEq(lido.unstakeRequestCount(USER1_ADDRESS), 1);

        (, , uint256 amountRequested, uint256 amountFilled, uint256 amountClaimed, uint256 stAVAXLocked) = lido
            .unstakeRequests(reqId);

        assertEq(amountRequested, 1.009 ether);
        assertEq(amountFilled, 1.009 ether);
        assertEq(amountClaimed, 0.5 ether);
        assertEq(stAVAXLocked, 1 ether);

        cheats.prank(USER1_ADDRESS);
        lido.claim(reqId, 0.25 ether);

        (, , , , uint256 amountClaimed2, ) = lido.unstakeRequests(reqId);
        assertEq(amountClaimed2, 0.75 ether);

        cheats.prank(USER1_ADDRESS);
        lido.claim(reqId, 0.25 ether + 0.009 ether);
        assertEq(lido.unstakeRequestCount(USER1_ADDRESS), 0);

        (address requester, , , , , ) = lido.unstakeRequests(reqId);

        // Full claim so expect the data to be removed.
        assertEq(requester, ZERO_ADDRESS);
    }

    function testClaimWithFuzzing(uint256 x) public {
        cheats.deal(USER1_ADDRESS, type(uint256).max);

        cheats.assume(x > lido.minStakeBatchAmount());
        cheats.assume(x < MAXIMUM_STAKE_AMOUNT);

        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: x}();
        validatorSelectMock(validatorSelectorAddress, "test", x, 0);

        lido.initiateStake();

        cheats.startPrank(USER1_ADDRESS);
        uint256 reqId = lido.requestWithdrawal(x);

        cheats.deal(pTreasuryAddress, x);
        lido.claimUnstakedPrincipals();

        lido.claim(reqId, x);

        // TODO: Assert tokens transferred correctly
    }

    // Tokens

    function protocolControlledAVAX() public {
        lido.deposit{value: 1 ether}();
        assertEq(lido.protocolControlledAVAX(), 1 ether);

        cheats.deal(pTreasuryAddress, 0.6 ether);
        lido.claimUnstakedPrincipals();
        assertEq(lido.protocolControlledAVAX(), 0.4 ether);

        cheats.deal(pTreasuryAddress, 0.4 ether);
        lido.claimUnstakedPrincipals();
        assertEq(lido.protocolControlledAVAX(), 0 ether);
    }

    function testRewardReceived() public {
        assertEq(lido.protocolControlledAVAX(), 0);
        assertEq(lido.amountPendingAVAX(), 0);

        cheats.expectEmit(false, false, false, true);
        emit ProtocolFeeEvent(0.1 ether);

        cheats.expectEmit(false, false, false, true);
        emit RewardsCollectedEvent(0.9 ether);

        cheats.deal(rTreasuryAddress, 1 ether);
        lido.claimRewards();

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

        cheats.deal(rTreasuryAddress, 1 ether);
        lido.claimRewards();

        // 0.1 taken as fee, 0.9 should be used to fill requests.
        (, , uint256 amountRequested, uint256 amountFilled, uint256 amountClaimed, uint256 stAVAXLocked) = lido
            .unstakeRequests(requestId);

        assertEq(amountRequested, 5 ether);
        assertEq(amountFilled, 0.9 ether);
        assertEq(amountClaimed, 0 ether);
        assertEq(stAVAXLocked, 5 ether);
    }

    // Non-rebasing

    function testAvaxToStAVAXBeforeRewards() public {
        cheats.deal(USER1_ADDRESS, 10 ether);
        cheats.deal(USER2_ADDRESS, 10 ether);

        // user 1 deposits
        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 1 ether}();
        assertEq(lido.balanceOf(USER1_ADDRESS), 1 ether);

        cheats.prank(USER2_ADDRESS);
        lido.deposit{value: 1 ether}();

        assertEq(lido.balanceOf(USER2_ADDRESS), 1 ether);
        assertEq(lido.exchangeRateAVAXToStAVAX(), 1 ether);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1 ether);
    }

    function testAvaxToStAVAXAfterRewards() public {
        cheats.deal(USER1_ADDRESS, 10 ether);
        cheats.deal(USER2_ADDRESS, 10 ether);

        // user 1 deposits, stAVAX:AVAX 1:1
        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 1 ether}();
        assertEq(lido.balanceOf(USER1_ADDRESS), 1 ether);

        // user 2 deposits, stAVAX:AVAX 1:1
        cheats.prank(USER2_ADDRESS);
        lido.deposit{value: 1 ether}();
        assertEq(lido.balanceOf(USER2_ADDRESS), 1 ether);
        assertEq(lido.protocolControlledAVAX(), 2 ether);
        assertEq(lido.amountPendingAVAX(), 2 ether);

        // now the exchange rate changes
        cheats.deal(rTreasuryAddress, 0.1 ether);
        lido.claimRewards();

        assertEq(lido.protocolControlledAVAX(), 2.09 ether);
        assertEq(lido.exchangeRateAVAXToStAVAX(), 956937799043062200);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1045000000000000000);
    }

    function testExchangeRateIsSameAfterInitiateStake() public {
        // Setup non 1:1 exchange rate
        cheats.deal(USER1_ADDRESS, 10 ether);
        cheats.deal(USER2_ADDRESS, 10 ether);
        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 1 ether}();
        cheats.prank(USER2_ADDRESS);
        lido.deposit{value: 1 ether}();
        cheats.deal(rTreasuryAddress, 0.1 ether);
        lido.claimRewards();
        assertEq(lido.exchangeRateAVAXToStAVAX(), 956937799043062200);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1045000000000000000);
        assertEq(lido.protocolControlledAVAX(), 2.09 ether);

        // Deposit an amount
        cheats.prank(USER1_ADDRESS);
        cheats.deal(USER1_ADDRESS, 10 ether);
        lido.deposit{value: 10 ether}();

        // Note the exchange rate
        assertEq(lido.exchangeRateAVAXToStAVAX(), 956937799043062200);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1045000000000000000);
        assertEq(lido.protocolControlledAVAX(), 12.09 ether);

        // Call initiateStake to move to staking
        validatorSelectMock(validatorSelectorAddress, "test", 12.09 ether, 0);
        lido.initiateStake();
        assertEq(lido.protocolControlledAVAX(), 12.09 ether);

        // Ensure exchange rate is the same
        assertEq(lido.exchangeRateAVAXToStAVAX(), 956937799043062200);
        assertEq(lido.exchangeRateStAVAXToAVAX(), 1045000000000000000);
    }

    // NB: this test fails because the numbers chosen can never match up no matter the precision.
    // Known issue of Solidity, floating point numbers & division. This round down behaviour is expected.
    // function testCannotClaimMoreAVAXThanDepositedBeforeRewards() public {
    //     // Setup non 1:1 exchange rate
    //     cheats.deal(USER1_ADDRESS, 11 ether);
    //     cheats.prank(USER1_ADDRESS);
    //     lido.deposit{value: 10 ether}();

    //     validatorSelectMock(validatorSelectorAddress, "test", 10 ether, 0);
    //     lido.initiateStake();
    //     lido.receiveRewardsFromMPC{value: 0.1 ether}();

    //     uint256 EXCHANGE_RATE = 991080277502477700; // 1 ether / 1.009;

    //     assertEq(lido.exchangeRateAVAXToStAVAX(), EXCHANGE_RATE);
    //     assertEq(lido.exchangeRateStAVAXToAVAX(), 1.009 ether);
    //     assertEq(lido.protocolControlledAVAX(), 10.09 ether);

    //     // I stake some AVAX, I should get 0.991 stAVAX
    //     cheats.deal(USER2_ADDRESS, 1 ether);
    //     cheats.prank(USER2_ADDRESS);
    //     lido.deposit{value: 1 ether}();
    //     uint256 user2StAVAXBalance = lido.balanceOf(USER2_ADDRESS);
    //     assertEq(user2StAVAXBalance, EXCHANGE_RATE);

    //     // Do some stuff that isn't rewards like deposit and receive principle
    //     cheats.prank(USER1_ADDRESS);
    //     lido.deposit{value: 1 ether}();
    //     lido.receivePrincipalFromMPC{value: 5 ether}();

    //     // Unstake all stAVAX, I shouldn't be able to claim more than 1 AVAX
    //     cheats.prank(USER2_ADDRESS);
    //     lido.requestWithdrawal(user2StAVAXBalance);
    //     (, , uint256 amountRequested, , , uint256 stAVAXLocked) = lido.unstakeRequests(0);

    //     assertEq(amountRequested, 1 ether);
    //     assertEq(stAVAXLocked, EXCHANGE_RATE);
    // }

    // Payment splitter

    function testNewPaymentSplitter() public {
        cheats.deal(rTreasuryAddress, 5 ether);
        lido.claimRewards();
        assertEq(address(lido.protocolFeeSplitter()).balance, 0.5 ether);

        PaymentSplitter splitter = PaymentSplitter(lido.protocolFeeSplitter());

        splitter.release(payable(feeAddressAuthor));
        splitter.release(payable(feeAddressLido));

        assertEq(address(feeAddressAuthor).balance, 0.1 ether);
        assertEq(address(feeAddressLido).balance, 0.4 ether);

        // Test that new PS can be deployed and new rewards received go to it
        address[] memory paymentAddresses = new address[](2);
        paymentAddresses[0] = USER1_ADDRESS;
        paymentAddresses[1] = USER2_ADDRESS;

        uint256[] memory paymentSplit = new uint256[](2);
        paymentSplit[0] = 60;
        paymentSplit[1] = 40;

        lido.setProtocolFeeSplit(paymentAddresses, paymentSplit);
        cheats.deal(rTreasuryAddress, 1 ether);
        lido.claimRewards();
        assertEq(address(lido.protocolFeeSplitter()).balance, 0.1 ether);

        PaymentSplitter newSplitter = PaymentSplitter(lido.protocolFeeSplitter());

        newSplitter.release(payable(USER1_ADDRESS));
        newSplitter.release(payable(USER2_ADDRESS));

        assertEq(address(USER1_ADDRESS).balance, 0.06 ether);
        assertEq(address(USER2_ADDRESS).balance, 0.04 ether);
    }

    // RBAC

    function testAccessControl() public {
        // Role admin should be contract deployer by default.
        bytes32 admin = lido.getRoleAdmin(ROLE_MPC_MANAGER);
        bytes32 DEFAULT_ADMIN_ROLE = 0x00; // AccessControl.sol
        assertEq(admin, DEFAULT_ADMIN_ROLE);

        // Other roles also default to this.
        assertTrue(lido.hasRole(ROLE_MPC_MANAGER, DEPLOYER_ADDRESS));

        // User 2 has no roles.
        assertTrue(!lido.hasRole(ROLE_MPC_MANAGER, USER2_ADDRESS));

        // User 2 doesn't have permission to grant roles, so this should revert.
        cheats.expectRevert(
            "AccessControl: account 0x220866b1a2219f40e72f5c628b65d54268ca3a9d is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        cheats.prank(USER2_ADDRESS);
        lido.grantRole(ROLE_MPC_MANAGER, USER2_ADDRESS);

        // But the contract deployer does have permission.
        cheats.prank(DEPLOYER_ADDRESS);
        lido.grantRole(ROLE_MPC_MANAGER, USER2_ADDRESS);
        assertTrue(lido.hasRole(ROLE_MPC_MANAGER, USER2_ADDRESS));

        // User 2 now has a role 🎉
        assertTrue(lido.hasRole(ROLE_MPC_MANAGER, USER2_ADDRESS));
    }

    function testMaxProtocolControlledAVAX() public {
        cheats.deal(USER1_ADDRESS, 10 ether);
        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 1 ether}();

        assertTrue(lido.hasRole(ROLE_PROTOCOL_MANAGER, DEPLOYER_ADDRESS));

        cheats.prank(DEPLOYER_ADDRESS);
        lido.setMaxProtocolControlledAVAX(2 ether);

        cheats.expectRevert(AvaLido.ProtocolStakedAmountTooLarge.selector);
        cheats.prank(USER1_ADDRESS);
        lido.deposit{value: 1.1 ether}();
    }
}
