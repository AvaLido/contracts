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
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

import "./test/console.sol";

struct UnstakeRequest {
    address requester; // The user who requested the unstake.
    uint256 amountRequested; // The amount of stAVAX requested to be unstaked.
    uint256 amountFilled; // The amount of free'd AVAX that has been allocated to this request.
    uint256 requestedAt; // The block.timestamp when the unstake request was made.
}

uint256 constant MINIMUM_STAKE_AMOUNT = 0.1 ether;
uint8 constant MAXIMUM_UNSTAKE_REQUESTS = 10;

/**
 * @title Lido on Avalanche
 * @author Hyperelliptic Labs and RockX
 */
contract AvaLido is Pausable, ReentrancyGuard {
    // Events
    event DepositEvent(address indexed _from, uint256 indexed _amount, uint256 timestamp);
    event WithdrawRequestSubmittedEvent(address indexed _from, uint256 indexed _amount, uint256 timestamp);

    // Errors
    error InvalidStakeAmount();
    error TooManyConcurrentUnstakeRequests();
    error NotAuthorized();
    error ClaimTooLarge();

    // Emitted to signal the MPC system to stake AVAX.
    // TODO: Move to mpc manager contract
    event StakeEvent(uint256 indexed amount);

    // WithdrawRequestFilled
    // WithdrawalRequestClaimed
    // WithdrawalRequestCompleted

    // States variables

    // The array of all unstake requests.
    // This acts as a queue, and we maintain a separate pointer
    // to point to the head of the queue rather than removing state
    // from the array. This allows us to:
    // - maintain an immutable order of requests.
    // - find the next requests to fill in constant time.
    UnstakeRequest[] public unstakeRequests;

    // Pointer to the head of the unfilled section of the queue.
    uint256 private unfilledHead = 0;

    // Record the number of unstake requests per user so that we can limit them to our max.
    mapping(address => uint8) public unstakeRequestCount;

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
        if (amount == 0) revert InvalidStakeAmount();

        // TODO: Transfer stAVAX from user to our contract.
        if (unstakeRequestCount[msg.sender] == MAXIMUM_UNSTAKE_REQUESTS) {
            revert TooManyConcurrentUnstakeRequests();
        }
        unstakeRequestCount[msg.sender]++;

        // Create the request and store in our queue.
        unstakeRequests.push(UnstakeRequest(msg.sender, amount, 0, block.timestamp));

        emit WithdrawRequestSubmittedEvent(msg.sender, amount, block.timestamp);

        return unstakeRequests.length - 1;
    }

    /**
     * @notice Look up an unstake request by index in the queue.
     * @dev As the queue is append-only, we can simply return the request at the given index.
     * @param requestIndex index The index of the request to look up.
     * @return UnstakeRequest The request at the given index.
     */
    function requestByIndex(uint256 requestIndex) external view returns (UnstakeRequest memory) {
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
        // TODO: Find request by ID
        UnstakeRequest memory request = this.requestByIndex(requestIndex);

        if (request.requester != msg.sender) revert NotAuthorized();
        if (amount > request.amountFilled) revert ClaimTooLarge();

        // Partial claim, update amounts.
        // TODO: Should we maintain 'amountClaimed' instead of changing these fields?
        // request.amountRequested -= amount;
        // request.amountFilled -= amount;

        // Burn {amount} stAVAX owned by the contract
        // Transfer {amount} stAVAX to the user

        // Emit claim event.
        if (amount == request.amountRequested) {
            // TODO.
            // Final claim, remove this request.
            unstakeRequestCount[msg.sender]--;
            return;
        }
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
        if (amount < MINIMUM_STAKE_AMOUNT) revert InvalidStakeAmount();

        // STAVAX.mint();
        // Send stAVAX to user

        emit DepositEvent(msg.sender, amount, block.timestamp);
        uint256 remaining = fillUnstakeRequests(amount);
        _stake(remaining);
    }

    /**
     * @notice You should not call this funciton.
     * @dev A payable function which receives AVAX from the MPC wallet and
     * uses it to fill unstake requests. Any remaining funds after all requests
     * are filled are re-staked.
     */
    function receiveFromMPC() external payable {
        // Fill unstake requests
        uint256 remaining = fillUnstakeRequests(msg.value);

        // Rebalance liquidity pool

        // Restake excess
        _stake(remaining);
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
        // Fill as many unstake requests as possible
        uint256 amountFilled = 0;
        uint256 remaining = inputAmount;

        // Assumes order of the array is creation order.
        for (uint256 i = unfilledHead; i < unstakeRequests.length; i++) {
            if (amountFilled == inputAmount) {
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
                }
            }

            remaining = inputAmount - amountFilled;
        }
        return remaining;
    }

    function isFilled(UnstakeRequest memory request) private pure returns (bool) {
        return request.amountFilled == request.amountRequested;
    }

    function _stake(uint256 amount) internal {
        if (amount <= 0) {
            return;
        }
        // TODO: Send AVAX to MPC wallet to be staked.
        emit StakeEvent(amount);
    }
}
