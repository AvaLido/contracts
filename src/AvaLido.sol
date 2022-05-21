// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/*
 █████╗ ██╗   ██╗ █████╗ ██╗     ██╗██████╗  ██████╗
██╔══██╗██║   ██║██╔══██╗██║     ██║██╔══██╗██╔═══██╗
███████║██║   ██║███████║██║     ██║██║  ██║██║   ██║
██╔══██║╚██╗ ██╔╝██╔══██║██║     ██║██║  ██║██║   ██║
██║  ██║ ╚████╔╝ ██║  ██║███████╗██║██████╔╝╚██████╔╝
╚═╝  ╚═╝  ╚═══╝  ╚═╝  ╚═╝╚══════╝╚═╝╚═════╝  ╚═════╝

                         ,██▄
                        /█████
                       ████████
                      ████████
                    ,████████   ,,
                   ▄████████   ████
                  ████████    ██████
                 ████████    ████████

              ████                 ,███
             ████████▌         ,████████
             ████████████,  █████████████
            ]████████████████████████████
             ████████████████████████████
             ███████████████████████████▌
              ██████████████████████████
               ███████████████████████
                 ███████████████████
                    ╙████████████
*/

import "openzeppelin-contracts/contracts/security/Pausable.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/finance/PaymentSplitter.sol";

import "./Types.sol";
import "./stAVAX.sol";
import "./interfaces/IValidatorSelector.sol";

uint256 constant MINIMUM_STAKE_AMOUNT = 0.1 ether;
uint256 constant MAXIMUM_STAKE_AMOUNT = 300_000_000 ether; // Roughly all circulating AVAX
uint256 constant STAKE_PERIOD = 14 days;
uint8 constant MAXIMUM_UNSTAKE_REQUESTS = 10;

/**
 * @title Lido on Avalanche
 * @author Hyperelliptic Labs and RockX
 */
contract AvaLido is Pausable, ReentrancyGuard, stAVAX, AccessControlEnumerable {
    // Errors
    error InvalidStakeAmount();
    error TooManyConcurrentUnstakeRequests();
    error NotAuthorized();
    error ClaimTooLarge();
    error InsufficientBalance();
    error NoAvailableValidators();

    // Events
    event DepositEvent(address indexed _from, uint256 _amount, uint256 timestamp);
    event WithdrawRequestSubmittedEvent(
        address indexed _from,
        uint256 _amount,
        uint256 timestamp,
        uint256 requestIndex
    );
    event RequestFilledEvent(uint256 indexed _fillAmount, uint256 timestamp);
    event ClaimEvent(address indexed _from, uint256 _claimAmount, bool indexed finalClaim, uint256 requestIndex);
    event RewardsCollectedEvent(uint256 amount);
    event ProtocolFeeEvent(uint256 amount);

    // Emitted to signal the MPC system to stake AVAX.
    // TODO: Move to mpc manager contract
    event StakeEvent(uint256 indexed amount, string indexed validator, uint256 stakeStartTime, uint256 stakeEndTime);

    // State variables

    // The array of all unstake requests.
    // This acts as a queue, and we maintain a separate pointer
    // to point to the head of the queue rather than removing state
    // from the array. This allows us to:
    // - maintain an immutable order of requests.
    // - find the next requests to fill in constant time.
    UnstakeRequest[] public unstakeRequests;

    // Pointer to the head of the unfilled section of the queue.
    uint256 private unfilledHead = 0;

    // Tracks the amount of AVAX being staked.
    // Also includes AVAX pending staking or unstaking.
    uint256 public amountStakedAVAX = 0;

    // Track the amount of AVAX in the contract which is waiting to be staked.
    // When the stake is triggered, this amount will be sent to the MPC system.
    uint256 public amountPendingAVAX = 0;

    // Record the number of unstake requests per user so that we can limit them to our max.
    mapping(address => uint8) public unstakeRequestCount;

    // Address which protocol fees are sent to.
    PaymentSplitter public protocolFeeSplitter;
    uint256 public protocolFeePercentage = 10;

    // Address where we'll send AVAX to be staked.
    address private mpcWalletAddress;

    // For gas efficiency, we won't emit staking events if the pending amount is below
    // this value.
    uint256 public minStakeBatchAmount = 10 ether;

    // Selector used to find validators to stake on.
    IValidatorSelector public validatorSelector;

    constructor(
        address lidoFeeAddress,
        address authorFeeAddress,
        address validatorSelectorAddress,
        address _mpcWalletAddress
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        mpcWalletAddress = _mpcWalletAddress;

        validatorSelector = IValidatorSelector(validatorSelectorAddress);

        address[] memory paymentAddresses = new address[](2);
        paymentAddresses[0] = lidoFeeAddress;
        paymentAddresses[1] = authorFeeAddress;

        uint256[] memory paymentSplit = new uint256[](2);
        paymentSplit[0] = 80;
        paymentSplit[1] = 20;
        protocolFeeSplitter = new PaymentSplitter(paymentAddresses, paymentSplit);
    }

    // -------------------------------------------------------------------------
    //  Modifiers
    // -------------------------------------------------------------------------

    modifier onlyAdmin() {
        // TODO: Define proper RBAC. For now just use deployer as admin.
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not admin");
        _;
    }

    // -------------------------------------------------------------------------
    //  Public functions
    // -------------------------------------------------------------------------

    /**
     * @notice Return your stAVAX to receive the equivalent amount of AVAX.
     * @dev We limit users to some maximum number of concurrent unstake requests to prevent
     * people flooding the queue. The amount for each unstake request is unbounded.
     * @param amount The amount of stAVAX to unstake.
     */
    function requestWithdrawal(uint256 amount) external whenNotPaused nonReentrant returns (uint256) {
        if (amount == 0 || amount > MAXIMUM_STAKE_AMOUNT) revert InvalidStakeAmount();

        if (unstakeRequestCount[msg.sender] == MAXIMUM_UNSTAKE_REQUESTS) {
            revert TooManyConcurrentUnstakeRequests();
        }
        unstakeRequestCount[msg.sender]++;

        if (balanceOf(msg.sender) < amount) {
            revert InsufficientBalance();
        }

        // Transfer stAVAX from user to our contract.
        // We use the internal call to avoid double-reentrancy issues.
        Shares256 sharesAmount = getSharesByAmount(amount);
        _transferShares(msg.sender, address(this), sharesAmount);

        // Create the request and store in our queue.
        unstakeRequests.push(UnstakeRequest(msg.sender, uint64(block.timestamp), amount, 0, 0));

        uint256 requestIndex = unstakeRequests.length - 1;
        emit WithdrawRequestSubmittedEvent(msg.sender, amount, block.timestamp, requestIndex);

        return requestIndex;
    }

    /**
     * @notice Look up an unstake request by index in the queue.
     * @dev As the queue is append-only, we can simply return the request at the given index.
     * @param requestIndex index The index of the request to look up.
     * @return UnstakeRequest The request at the given index.
     */
    function requestByIndex(uint256 requestIndex) public view returns (UnstakeRequest memory) {
        return unstakeRequests[requestIndex];
    }

    /**
     * @notice Claim your AVAX from a completed unstake requested.
     * @dev This allows users to claim their AVAX back. We burn the stAVAX that we've been holding
     * at this point, so that the amount of AVAX in the protocol aligns with the amount of stAVAX
     * in circulation, and rebases can be computed properly.
     * Note that we also allow partial claims of unstake requests so that users don't need to wait
     * for the entire request to be filled to get some liquidity.
     */
    function claim(uint256 requestIndex, uint256 amount) external whenNotPaused nonReentrant {
        UnstakeRequest memory request = requestByIndex(requestIndex);

        if (request.requester != msg.sender) revert NotAuthorized();
        if (amount > request.amountFilled - request.amountClaimed) revert ClaimTooLarge();
        if (amount > address(this).balance) revert InsufficientBalance();

        // Partial claim, update amounts.
        request.amountClaimed += amount;
        unstakeRequests[requestIndex] = request;

        // Burn stAVAX and send AVAX to the user.
        Shares256 shares = getSharesByAmount(amount);
        _burnShares(address(this), shares);
        payable(msg.sender).transfer(amount);

        // Emit claim event.
        if (isFullyClaimed(request)) {
            // Final claim, remove this request.
            // Note that we just delete for gas refunds, this doesn't alter the indicies of
            // the other requests.
            unstakeRequestCount[msg.sender]--;
            delete unstakeRequests[requestIndex];

            emit ClaimEvent(msg.sender, amount, true, requestIndex);

            return;
        }

        // Emit an event which describes the partial claim.
        emit ClaimEvent(msg.sender, amount, false, requestIndex);
    }

    /**
     * @notice Calculate the amount of AVAX controlled by the protocol.
     * @dev This is the amount of AVAX staked (or technically pending being staked),
     * plus the amount of AVAX that is in the contract. This _does_ include the AVAX
     * in the contract which has been allocated to unstake requests, but not yet claimed,
     * because we don't burn stAVAX until the claim happens.
     * *This should always be >= the total supply of stAVAX*.
     */
    function protocolControlledAVAX() public view override returns (uint256) {
        return amountStakedAVAX + address(this).balance;
    }

    /**
     * @notice Initiate execution of staking for all pending AVAX.
     * @return uint256 The amount of AVAX that was staked.
     * @dev This function takes all pending AVAX and attempts to allocate it to validators.
     * The funds are then transferred to the MPC system for cross-chain transport and staking.
     * Note that this function is publicly available, meaning anyone can pay gas to initiate the
     * staking operation and we don't require any special permissions.
     * It would be sensible for our team to also call this at a regular interval.
     */
    function initiateStake() external whenNotPaused nonReentrant returns (uint256) {
        if (amountPendingAVAX == 0 || amountPendingAVAX < minStakeBatchAmount) {
            return 0;
        }

        (string[] memory ids, uint256[] memory amounts, uint256 remaining) = validatorSelector.selectValidatorsForStake(
            amountPendingAVAX
        );

        if (ids.length == 0 || amounts.length == 0) revert NoAvailableValidators();

        uint256 totalToStake = amountPendingAVAX - remaining;

        // Transfer stAVAX from our contract to the MPC wallet and record it as staked.
        payable(mpcWalletAddress).transfer(totalToStake);
        amountStakedAVAX += totalToStake;

        // Our pending AVAX is now whatever we couldn't allocate.
        amountPendingAVAX = remaining;

        // Add some buffer to account for delay in exporting to P-chain and MPC consensus.
        // TODO: Make configurable?
        uint256 startTime = block.timestamp + 30 minutes;
        uint256 endTime = startTime + STAKE_PERIOD;
        for (uint256 i = 0; i < ids.length; i++) {
            emit StakeEvent(amounts[i], ids[i], startTime, endTime);
        }

        return totalToStake;
    }

    // -------------------------------------------------------------------------
    //  Payable functions
    // -------------------------------------------------------------------------

    /**
     * @notice Depsoit your AXAV to receive Staked AVAX (stAVAX) in return.
     * You will always receive stAVAX in a 1:1 ratio.
     * @dev Receives AVAX and mints StAVAX to msg.sender. We attempt to fill
     * any outstanding requests with the incoming AVAX for instant liquidity.
     */
    function deposit() external payable whenNotPaused nonReentrant {
        uint256 amount = msg.value;
        if (amount < MINIMUM_STAKE_AMOUNT || amount > MAXIMUM_STAKE_AMOUNT) revert InvalidStakeAmount();

        // Mint stAVAX for user
        Shares256 shares = _getDepositSharesByAmount(amount);
        _mintShares(msg.sender, shares);

        emit DepositEvent(msg.sender, amount, block.timestamp);
        uint256 remaining = fillUnstakeRequests(amount);

        // Take the remaining amount and stash it to be staked at a later time.
        // Note that we explcitly do not subsequently use this pending amount to fill unstake requests.
        // This intentionally removes the ability to instantly stake and unstake, which makes the
        // arb opportunity around trying to collect rebase value significantly riskier/impractical.
        amountPendingAVAX += remaining;
    }

    /**
     * @notice You should not call this funciton.
     * @dev A payable function which receives AVAX from the MPC wallet and
     * uses it to fill unstake requests. Any remaining funds after all requests
     * are filled are re-staked.
     */
    function receivePrincipalFromMPC() external payable {
        if (amountStakedAVAX == 0 || amountStakedAVAX < msg.value) revert InvalidStakeAmount();

        // We received this from an unstake, so remove from our count.
        // Anything restaked will be counted again on the way out.
        // Note: This avoids double counting, as the total count includes AVAX held by
        // the contract.
        amountStakedAVAX -= msg.value;

        // Fill unstake requests
        uint256 remaining = fillUnstakeRequests(msg.value);

        // Allocate excess for restaking.
        amountPendingAVAX += remaining;
    }

    /**
     * @notice You should not call this funciton.
     * @dev this function takes the protocol fee from the rewards, distributes
     * it to the protocol fee splitters, and then retains the rest.
     * We then kick off our stAVAX rebase.
     */
    function receiveRewardsFromMPC() external payable {
        if (msg.value == 0) return;

        uint256 protocolFee = (msg.value * protocolFeePercentage) / 100;
        payable(protocolFeeSplitter).transfer(protocolFee);
        emit ProtocolFeeEvent(protocolFee);

        uint256 afterFee = msg.value - protocolFee;
        emit RewardsCollectedEvent(afterFee);

        // Fill unstake requests
        uint256 remaining = fillUnstakeRequests(afterFee);

        // Allocate excess for restaking.
        amountPendingAVAX += remaining;
    }

    // -------------------------------------------------------------------------
    //  Private/internal functions
    // -------------------------------------------------------------------------

    /**
     * @dev Fills the next available unstake request with the given amount.
     * This function works by reading the `unstakeRequests` queue, in-order, starting
     * from the `unfilledHead` pointer. When a request is completely filled, we update
     * the `unfilledHead` pointer to the next request.
     * Note that filled requests are not removed from the queue, as they still must be
     * claimed by users.
     * @param inputAmount The amount of free'd AVAX made available to fill requests.
     */
    function fillUnstakeRequests(uint256 inputAmount) private returns (uint256) {
        if (inputAmount == 0) return 0;

        uint256 amountFilled = 0;
        uint256 remaining = inputAmount;

        // Assumes order of the array is creation order.
        for (uint256 i = unfilledHead; i < unstakeRequests.length; i++) {
            if (remaining == 0) break;

            if (isFilled(unstakeRequests[i])) {
                // This shouldn't happen, but revert if it does for clearer testing
                revert("Invalid state - filled request in queue");
            }

            if (unstakeRequests[i].amountFilled < unstakeRequests[i].amountRequested) {
                uint256 amountRequired = unstakeRequests[i].amountRequested - unstakeRequests[i].amountFilled;

                uint256 amountToFill = Math.min(amountRequired, remaining);
                amountFilled += amountToFill;

                unstakeRequests[i].amountFilled += amountToFill;

                // We filled the request entirely, so move the head pointer on
                if (isFilled(unstakeRequests[i])) {
                    unfilledHead = i + 1;
                    emit RequestFilledEvent(amountToFill, block.timestamp);
                }
            }

            remaining = inputAmount - amountFilled;
        }
        return remaining;
    }

    function isFilled(UnstakeRequest memory request) private pure returns (bool) {
        return request.amountFilled >= request.amountRequested;
    }

    function isFullyClaimed(UnstakeRequest memory request) private pure returns (bool) {
        return request.amountClaimed >= request.amountRequested;
    }

    // -------------------------------------------------------------------------
    //  Admin functions
    // -------------------------------------------------------------------------

    function setProtocolFeePercentage(uint256 _protocolFeePercentage) external onlyAdmin {
        require(_protocolFeePercentage <= 100);
        protocolFeePercentage = _protocolFeePercentage;
    }

    function setMPCWalletAddress(address _mpcWalletAddress) external onlyAdmin {
        require(_mpcWalletAddress != address(0), "Cannot set to 0 address");
        mpcWalletAddress = _mpcWalletAddress;
    }

    function setMinStakeBatchAmount(uint256 _minStakeBatchAmount) external onlyAdmin {
        minStakeBatchAmount = _minStakeBatchAmount;
    }
}
