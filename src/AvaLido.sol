// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;


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


import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuard.sol";

contract AvaLido is PausableUpgradeable, ReentrancyGuardUpgradeable {
    // main contract that is single source of truth for state variables,
    // coordinates other contracts, accepts deposits and withdrawal requests, etc.

    // Events

    event DepositEvent(address indexed _from, uint256 indexed _amount);
    event WithdrawRequestSubmittedEvent(address indexed _from, uint256 indexed _amount, uint256 timestamp);
    // WithdrawRequestFilled
    // WithdrawalRequestClaimed
    // WithdrawalRequestCompleted
    
    // States variables

    /**
     * @dev Receives AVAX and mints StAVAX to msg.sender
     * @param amount - Amount of AVAX sent from msg.sender
     * @return Amount of StAVAX shares generated
     */
    function deposit(uint256 amount)
        external
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        require(_amount > 0, "Invalid amount");

        // 1. convertAvaxToStAvax
        // 2. mint stAVAX to user
        // 3. do some calculations and either use the deposit money to fill withdrawal requests or be staked

        emit SubmitEvent(msg.sender, amount);
        // 4. returns amount of stAVAX shares generated
    }

    /**
     * @dev Requests to unstake an amount of AVAX.
     */
    function requestWithdrawal(uint256 amount, uint256 timestamp)
        external
        whenNotPaused
        nonReentrant
    {
        // 1. convertStAvaxToAvax
        // 2. burn stAVAX
        // 3. add request to withdrawal queue
        
        emit WithdrawRequestSubmittedEvent(msg.sender, amount, timestamp);
    }
}
