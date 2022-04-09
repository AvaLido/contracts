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

struct UnstakeRequest {
    address requester;
    uint32 id;
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

    // WithdrawRequestFilled
    // WithdrawalRequestClaimed
    // WithdrawalRequestCompleted

    // States variables
    UnstakeRequest[] private unstakeRequests;
    mapping(address => uint32) private nextUserRequestId;
    mapping(address => uint32[]) public userRequests;

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
    function requestWithdrawal(uint256 amount) external whenNotPaused nonReentrant {
        // TODO: Transfer stAVAX from user to our contract.

        // Find the next Id for the unstake request.
        uint32 currentId = nextUserRequestId[msg.sender];
        nextUserRequestId[msg.sender] = currentId + 1;

        // Create the request and store in our list.
        UnstakeRequest memory newRequest = UnstakeRequest(msg.sender, currentId, amount, 0, block.timestamp);
        unstakeRequests.push(newRequest);

        // Record some metadata about the request so we can find it more easily.
        uint32[] memory currentRequests = userRequests[msg.sender];
        uint32[] memory newRequests = new uint32[](currentRequests.length + 1);
        for (uint32 i = 0; i < currentRequests.length; i++) {
            newRequests[i] = currentRequests[i];
        }
        newRequests[currentRequests.length] = currentId;

        emit WithdrawRequestSubmittedEvent(msg.sender, amount, block.timestamp);
    }

    function requestById(uint32 requestId) external view returns (UnstakeRequest memory) {
        for (uint32 i = 0; i < unstakeRequests.length; i++) {
            if (unstakeRequests[i].id == requestId) {
                return unstakeRequests[i];
            }
        }
        revert("Request not found");
    }

    function claim(uint32 requestId, uint256 amount) external whenNotPaused nonReentrant {
        // TODO: Find request by ID
        UnstakeRequest memory request = this.requestById(requestId);

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

        // TODO: Assumes order of the array is creation order.
        for (uint256 i = 0; i < unstakeRequests.length; i++) {
            if (amountFilled == inputAmount) {
                break;
            }
            remaining = inputAmount - amountFilled;

            if (unstakeRequests[i].amountFilled < unstakeRequests[i].amountRequested) {
                uint256 amountRequired = unstakeRequests[i].amountRequested - unstakeRequests[i].amountFilled;

                uint256 amountToFill = Math.min(amountRequired, remaining);
                amountFilled += amountToFill;

                unstakeRequests[i].amountFilled += amountToFill;
            }
        }

        return remaining;
    }

    function _stake(uint256 amount) internal {
        // TODO: Send AVAX to MPC wallet to be staked.
    }
}
