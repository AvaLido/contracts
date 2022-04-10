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
    address requester;
    uint256 amountRequested;
    uint256 amountFilled;
    uint256 requestedAt;
}

contract AvaLido is Pausable, ReentrancyGuard {
    // main contract that is single source of truth for state variables,
    // coordinates other contracts, accepts deposits and withdrawal requests, etc.

    // Events

    event DepositEvent(address indexed _from, uint256 indexed _amount);
    event WithdrawRequestSubmittedEvent(address indexed _from, uint256 indexed _amount, uint256 timestamp);

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
    // - Use a mapping to store indicies for point lookups.
    UnstakeRequest[] public unstakeRequests;

    // Pointer to the head of the unfilled section of the queue.
    uint256 private unfilledHead = 0;

    /**
     * @dev Receives AVAX and mints StAVAX to msg.sender
     * @param amount - Amount of AVAX sent from msg.sender
     */
    function deposit(uint256 amount) external payable whenNotPaused nonReentrant {
        require(amount > 0, "Invalid amount");
        require(amount == msg.value, "Not enough AVAX sent");

        // STAVAX.mint();
        // Send stAVAX to user

        emit DepositEvent(msg.sender, amount);
        uint256 remaining = fillUnstakeRequests(amount);
        _stake(remaining);
    }

    /**
     * @dev Requests to unstake an amount of AVAX.
     */
    function requestWithdrawal(uint256 amount) external whenNotPaused nonReentrant returns (uint256) {
        // TODO: Transfer stAVAX from user to our contract.

        // Create the request and store in our list.
        unstakeRequests.push(UnstakeRequest(msg.sender, amount, 0, block.timestamp));

        emit WithdrawRequestSubmittedEvent(msg.sender, amount, block.timestamp);

        return unstakeRequests.length - 1;
    }

    function requestByIndex(uint32 requestIndex) external view returns (UnstakeRequest memory) {
        return unstakeRequests[requestIndex];
    }

    function claim(uint32 requestIndex, uint256 amount) external whenNotPaused nonReentrant {
        // TODO: Find request by ID
        UnstakeRequest memory request = this.requestByIndex(requestIndex);

        require(request.requester == msg.sender, "Can only claim your own requests");
        require(amount <= request.amountFilled, "Can only claim what is filled");

        // Partial claim, update amounts.
        // TODO: Should we maintain 'amountClaimed' instead of changing these fields?
        request.amountRequested -= amount;
        request.amountFilled -= amount;

        // Burn {amount} stAVAX owned by the contract
        // Transfer {amount} stAVAX to the user

        // Emit claim event.
        if (request.amountFilled + amount == request.amountRequested) {
            // TODO.
            // Final claim, remove this request.
            return;
        }
    }

    function fillUnstakeRequests(uint256 inputAmount) private returns (uint256) {
        // Fill as many unstake requests as possible
        uint256 amountFilled = 0;
        uint256 remaining = inputAmount;

        // Assumes order of the array is creation order.
        for (uint256 i = unfilledHead; i < unstakeRequests.length; i++) {
            if (amountFilled == inputAmount) {
                revert("Invalid state - filled request in queue");
            }

            if (unstakeRequests[i].amountFilled < unstakeRequests[i].amountRequested) {
                uint256 amountRequired = unstakeRequests[i].amountRequested - unstakeRequests[i].amountFilled;

                uint256 amountToFill = Math.min(amountRequired, remaining);
                amountFilled += amountToFill;

                unstakeRequests[i].amountFilled += amountToFill;

                // We filled the request entirely, so move the head pointer on
                if (unstakeRequests[i].amountFilled == unstakeRequests[i].amountRequested) {
                    unfilledHead = i + 1;
                }
            }

            remaining = inputAmount - amountFilled;
        }
        return remaining;
    }

    function receiveFromMPC() external payable {
        // Fill unstake requests
        uint256 remaining = fillUnstakeRequests(msg.value);
        // Rebalance liquidity pool

        // Restake excess
        _stake(remaining);
    }

    function _stake(uint256 amount) internal {
        if (amount <= 0) {
            return;
        }
        // TODO: Send AVAX to MPC wallet to be staked.
        emit StakeEvent(amount);
    }
}
