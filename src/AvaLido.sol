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
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import "./Types.sol";
import "./Roles.sol";
import "./stAVAX.sol";
import "./interfaces/IValidatorSelector.sol";
import "./interfaces/IMpcManager.sol";
import "./interfaces/ITreasury.sol";

/**
 * @title Lido on Avalanche
 * @author Hyperelliptic Labs and RockX
 */
contract AvaLido is Pausable, ReentrancyGuard, stAVAX, AccessControlEnumerable {
    // Errors
    error InvalidStakeAmount();
    error ProtocolStakedAmountTooLarge();
    error TooManyConcurrentUnstakeRequests();
    error NotAuthorized();
    error ClaimTooLarge();
    error ClaimTooSoon(uint64 availableAt);
    error InsufficientBalance();
    error NoAvailableValidators();
    error InvalidAddress();
    error InvalidConfiguration();

    // Events
    event DepositEvent(address indexed from, uint256 amount, uint256 timestamp);
    event WithdrawRequestSubmittedEvent(
        address indexed from,
        uint256 avaxAmount,
        uint256 stAvaxAmount,
        uint256 timestamp,
        uint256 requestIndex
    );
    event RequestFullyFilledEvent(uint256 requestedAmount, uint256 timestamp, uint256 indexed requestIndex);
    event RequestPartiallyFilledEvent(uint256 fillAmount, uint256 timestamp, uint256 indexed requestIndex);
    event ClaimEvent(address indexed from, uint256 claimAmount, bool indexed finalClaim, uint256 indexed requestIndex);
    event RewardsCollectedEvent(uint256 amount);
    event ProtocolFeeEvent(uint256 amount);
    event SetProtocolFeeBasisPoints(uint256 newProtocolFeeBasisPoints);
    event SetPrincipalTreasuryAddress(address newPrincipalTreasuryAddress);
    event SetRewardTreasuryAddress(address newRewardTreasuryAddress);
    event SetProtocolFeeSplit(address[] newPaymentAddresses, uint256[] newPaymentSplit);
    event SetMinStakeBatchAmount(uint256 newMinStakeBatchAmount);
    event SetMinStakeAmount(uint256 newMinStakeAmount);
    event SetStakePeriod(uint256 newStakePeriod);
    event SetMaxUnstakeRequests(uint8 newMaxUnstakeRequests);
    event SetMaxProtocolControlledAVAX(uint256 newMaxProtocolControlledAVAX);

    // State variables

    // The array of all unstake requests. This acts as a queue, and we maintain a separate pointer
    // to point to the head of the queue rather than removing state from the array. This allows us to:
    // - maintain an immutable order of requests.
    // - find the next requests to fill in constant time.
    UnstakeRequest[] public unstakeRequests;

    // Pointer to the head of the unfilled section of the queue.
    uint256 private unfilledHead;

    // Tracks the amount of AVAX being staked. Also includes AVAX pending staking or unstaking.
    uint256 public amountStakedAVAX;

    // Track the amount of AVAX in the contract which is waiting to be staked.
    // When the stake is triggered, this amount will be sent to the MPC system.
    uint256 public amountPendingAVAX;

    // Record the number of unstake requests per user so that we can limit them to our max.
    mapping(address => uint8) public unstakeRequestCount;

    // Protocol fee is expressed as basis points (BPS). One BPS is 1/100 of 1%.
    uint256 public protocolFeeBasisPoints;

    // Addresses which protocol fees are sent to.
    // Protocol fee split is set out in the "Lido for Avalance" proposal:
    // https://research.lido.fi/t/lido-for-avalanche-joint-proposal-by-hyperelliptic-labs-and-rockx/1610
    PaymentSplitter public protocolFeeSplitter;

    // For gas efficiency, we won't emit staking events if the pending amount is below this value.
    uint256 public minStakeBatchAmount;

    // Smallest amount a user can stake.
    uint256 public minStakeAmount;

    // Period over which AVAX is staked.
    uint256 public stakePeriod;

    // Control in the case that we want to slow rollout.
    uint256 public maxProtocolControlledAVAX;

    // Maximum unstake requests a user can open at once (prevents spamming).
    uint8 public maxUnstakeRequests;

    // Time that an unstaker must wait before being able to claim.
    uint64 public minimumClaimWaitTimeSeconds;

    // The buffer added to account for delay in exporting to P-chain
    uint256 pChainExportBuffer;

    // Selector used to find validators to stake on.
    IValidatorSelector public validatorSelector;

    // Address where we'll send AVAX to be staked.
    address private mpcManagerAddress;
    IMpcManager public mpcManager;
    ITreasury public principalTreasury;
    ITreasury public rewardTreasury;

    function initialize(
        address lidoFeeAddress,
        address authorFeeAddress,
        address validatorSelectorAddress,
        address _mpcManagerAddress
    ) public initializer {
        __ERC20_init("Staked AVAX", "stAVAX");

        // Roles
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ROLE_PAUSE_MANAGER, msg.sender);
        _setupRole(ROLE_RESUME_MANAGER, msg.sender);
        _setupRole(ROLE_FEE_MANAGER, msg.sender);
        _setupRole(ROLE_TREASURY_MANAGER, msg.sender);
        _setupRole(ROLE_MPC_MANAGER, msg.sender);
        _setupRole(ROLE_PROTOCOL_MANAGER, msg.sender);

        // Initialize contract variables.
        protocolFeeBasisPoints = 1000; // 1000 BPS = 10%
        minStakeBatchAmount = 10 ether;
        minStakeAmount = 0.1 ether;
        stakePeriod = 14 days;
        maxUnstakeRequests = 10;
        maxProtocolControlledAVAX = 100_000 ether; // Initial limit for deploy.
        pChainExportBuffer = 1 hours;
        minimumClaimWaitTimeSeconds = 3600;

        mpcManager = IMpcManager(_mpcManagerAddress);
        validatorSelector = IValidatorSelector(validatorSelectorAddress);

        // Initial payment addresses and fee split.
        address[] memory paymentAddresses = new address[](2);
        paymentAddresses[0] = lidoFeeAddress;
        paymentAddresses[1] = authorFeeAddress;

        uint256[] memory paymentSplit = new uint256[](2);
        paymentSplit[0] = 80;
        paymentSplit[1] = 20;

        setProtocolFeeSplit(paymentAddresses, paymentSplit);
    }

    // -------------------------------------------------------------------------
    //  Public functions
    // -------------------------------------------------------------------------

    /**
     * @notice Return your stAVAX to receive the equivalent amount of AVAX at the current exchange rate.
     * @dev We limit users to some maximum number of concurrent unstake requests to prevent
     * people flooding the queue. The amount for each unstake request is unbounded.
     * @param stAVAXAmount The amount of stAVAX to unstake.
     */
    function requestWithdrawal(uint256 stAVAXAmount) external whenNotPaused nonReentrant returns (uint256) {
        if (stAVAXAmount == 0) revert InvalidStakeAmount();

        if (unstakeRequestCount[msg.sender] >= maxUnstakeRequests) {
            revert TooManyConcurrentUnstakeRequests();
        }
        unstakeRequestCount[msg.sender]++;

        if (balanceOf(msg.sender) < stAVAXAmount) {
            revert InsufficientBalance();
        }

        // Transfer stAVAX from user to our contract.
        _transfer(msg.sender, address(this), stAVAXAmount);
        uint256 avaxAmount = stAVAXToAVAX(protocolControlledAVAX(), stAVAXAmount);

        // Create the request and store in our queue.
        unstakeRequests.push(UnstakeRequest(msg.sender, uint64(block.timestamp), avaxAmount, 0, 0, stAVAXAmount));

        uint256 requestIndex = unstakeRequests.length - 1;
        emit WithdrawRequestSubmittedEvent(msg.sender, avaxAmount, stAVAXAmount, block.timestamp, requestIndex);

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
     * at this point.
     * Note that we also allow partial claims of unstake requests so that users don't need to wait
     * for the entire request to be filled to get some liquidity. This is one of the reasons we set the
     * exchange rate in requestWithdrawal instead of at claim time. (The other is so that unstakers don't
     * earn rewards).
     */
    function claim(uint256 requestIndex, uint256 amountAVAX) external whenNotPaused nonReentrant {
        UnstakeRequest memory request = requestByIndex(requestIndex);

        if (request.requester != msg.sender) revert NotAuthorized();
        if (amountAVAX > request.amountFilled - request.amountClaimed) revert ClaimTooLarge();
        if (amountAVAX > address(this).balance) revert InsufficientBalance();

        uint64 availableAt = request.requestedAt + minimumClaimWaitTimeSeconds;
        if (block.timestamp < availableAt) revert ClaimTooSoon({availableAt: availableAt});

        // Partial claim, update amounts.
        request.amountClaimed += amountAVAX;
        unstakeRequests[requestIndex] = request;

        // Burn the stAVAX in the UnstakeRequest. If it's a partial claim we need to burn a proportional amount
        // of the original stAVAX using the stAVAX and AVAX amounts in the unstake request.
        uint256 amountOfStAVAXToBurn = Math.mulDiv(request.stAVAXLocked, amountAVAX, request.amountRequested);

        // In the case that a user claims all but one wei of their avax, and then claims 1 wei separately, we
        // will incorrectly round down the amount of stAVAX to burn, leading to a left over amount of 1 wei stAVAX
        // in the contract, and a request which can never be fully claimed. I don't know why anyone would do this,
        // but maybe this will keep our internal accounting more in order.
        if (amountOfStAVAXToBurn == 0) {
            amountOfStAVAXToBurn = 1;
        }
        _burn(address(this), amountOfStAVAXToBurn);

        // Transfer the AVAX to the user
        payable(msg.sender).transfer(amountAVAX);

        // Emit claim event.
        if (isFullyClaimed(request)) {
            // Final claim, remove this request.
            // Note that we just delete for gas refunds, this doesn't alter the indicies of the other requests.
            unstakeRequestCount[msg.sender]--;
            delete unstakeRequests[requestIndex];

            emit ClaimEvent(msg.sender, amountAVAX, true, requestIndex);

            return;
        }

        // Emit an event which describes the partial claim.
        emit ClaimEvent(msg.sender, amountAVAX, false, requestIndex);
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

        amountStakedAVAX += totalToStake;

        // Our pending AVAX is now whatever we couldn't allocate.
        amountPendingAVAX = remaining;

        // Add some buffer to account for delay in exporting to P-chain and MPC consensus.
        uint256 startTime = block.timestamp + pChainExportBuffer;
        uint256 endTime = startTime + stakePeriod;
        for (uint256 i = 0; i < ids.length; i++) {
            // The array from selectValidatorsForStake may be sparse, so we need to ignore any validators
            // which are set with 0 amounts.
            if (amounts[i] == 0) {
                continue;
            }
            mpcManager.requestStake{value: amounts[i]}(ids[i], amounts[i], startTime, endTime);
        }

        return totalToStake;
    }

    // -------------------------------------------------------------------------
    //  Payable functions
    // -------------------------------------------------------------------------

    /**
     * @notice Deposit your AVAX to receive Staked AVAX (stAVAX) in return.
     * @dev Receives AVAX and mints StAVAX to msg.sender. We attempt to fill
     * any outstanding requests with the incoming AVAX for instant liquidity.
     */
    function deposit() external payable whenNotPaused nonReentrant {
        uint256 amount = msg.value;
        if (amount < minStakeAmount) revert InvalidStakeAmount();
        if (protocolControlledAVAX() + amount > maxProtocolControlledAVAX) revert ProtocolStakedAmountTooLarge();

        // Mint stAVAX for user at the currently calculated exchange rate
        // We don't want to count this deposit in protocolControlledAVAX()
        uint256 amountOfStAVAXToMint = avaxToStAVAX(protocolControlledAVAX() - amount, amount);
        _mint(msg.sender, amountOfStAVAXToMint);

        emit DepositEvent(msg.sender, amount, block.timestamp);
        uint256 remaining = fillUnstakeRequests(amount);

        // Take the remaining amount and stash it to be staked at a later time.
        // Note that we explicitly do not subsequently use this pending amount to fill unstake requests.
        // This intentionally removes the ability to instantly stake and unstake, which makes the
        // arb opportunity around trying to collect rebase value significantly riskier/impractical.
        amountPendingAVAX += remaining;
    }

    /**
     * @notice Claims the value in treasury.
     * @dev A payable function which receives AVAX from the MPC wallet and
     * uses it to fill unstake requests. Any remaining funds after all requests
     * are filled are re-staked.
     */
    function claimUnstakedPrincipals() external {
        uint256 val = address(principalTreasury).balance;
        if (val == 0) return;
        if (amountStakedAVAX == 0 || amountStakedAVAX < val) revert InvalidStakeAmount();

        principalTreasury.claim(val);

        // We received this from an unstake, so remove from our count.
        // Anything restaked will be counted again on the way out.
        // Note: This avoids double counting, as the total count includes AVAX held by
        // the contract.
        amountStakedAVAX -= val;

        // Fill unstake requests
        uint256 remaining = fillUnstakeRequests(val);

        // Allocate excess for restaking.
        amountPendingAVAX += remaining;
    }

    /**
     * @notice Claims the value in treasury and distribute.
     * @dev this function takes the protocol fee from the rewards, distributes
     * it to the protocol fee splitters, and then retains the rest.
     * We then kick off our stAVAX rebase.
     */
    function claimRewards() external {
        uint256 val = address(rewardTreasury).balance;
        if (val == 0) return;
        rewardTreasury.claim(val);

        uint256 protocolFee = (val * protocolFeeBasisPoints) / 10_000;
        payable(protocolFeeSplitter).transfer(protocolFee);
        emit ProtocolFeeEvent(protocolFee);

        uint256 afterFee = val - protocolFee;
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

            if (unstakeRequests[i].amountFilled < unstakeRequests[i].amountRequested) {
                uint256 amountRequired = unstakeRequests[i].amountRequested - unstakeRequests[i].amountFilled;

                uint256 amountToFill = Math.min(amountRequired, remaining);
                amountFilled += amountToFill;

                unstakeRequests[i].amountFilled += amountToFill;

                // We filled the request entirely, so move the head pointer on
                if (isFilled(unstakeRequests[i])) {
                    unfilledHead = i + 1;
                    emit RequestFullyFilledEvent(unstakeRequests[i].amountRequested, block.timestamp, i);
                } else {
                    emit RequestPartiallyFilledEvent(amountToFill, block.timestamp, i);
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

    function exchangeRateAVAXToStAVAX() external view returns (uint256) {
        return avaxToStAVAX(protocolControlledAVAX(), 1 ether);
    }

    function exchangeRateStAVAXToAVAX() external view returns (uint256) {
        return stAVAXToAVAX(protocolControlledAVAX(), 1 ether);
    }

    // -------------------------------------------------------------------------
    //  Admin functions
    // -------------------------------------------------------------------------

    function pause() external onlyRole(ROLE_PAUSE_MANAGER) {
        _pause();
    }

    function resume() external onlyRole(ROLE_RESUME_MANAGER) {
        _unpause();
    }

    function setProtocolFeeBasisPoints(uint256 _protocolFeeBasisPoints) external onlyRole(ROLE_FEE_MANAGER) {
        require(_protocolFeeBasisPoints <= 10_000);
        protocolFeeBasisPoints = _protocolFeeBasisPoints;

        emit SetProtocolFeeBasisPoints(_protocolFeeBasisPoints);
    }

    /**
     * @dev The two treasury addresses should be set in intialize. Separate them due to
     * stack too deep issue. Need to check if there's a better way to handle, e.g. use a
     * struct to hold all the arguments of initialize call?
     */
    function setPrincipalTreasuryAddress(address _address) external onlyRole(ROLE_TREASURY_MANAGER) {
        if (_address == address(0)) revert InvalidAddress();

        principalTreasury = ITreasury(_address);

        emit SetPrincipalTreasuryAddress(_address);
    }

    /**
     * @dev The two treasury addresses should be set in intialize. Separate them due to
     * stack too deep issue. Need to check if there's a better way to handle, e.g. use a
     * struct to hold all the arguments of initialize call?
     */
    function setRewardTreasuryAddress(address _address) external onlyRole(ROLE_TREASURY_MANAGER) {
        if (_address == address(0)) revert InvalidAddress();

        rewardTreasury = ITreasury(_address);

        emit SetRewardTreasuryAddress(_address);
    }

    function setProtocolFeeSplit(address[] memory paymentAddresses, uint256[] memory paymentSplit)
        public
        onlyRole(ROLE_TREASURY_MANAGER)
    {
        protocolFeeSplitter = new PaymentSplitter(paymentAddresses, paymentSplit);

        emit SetProtocolFeeSplit(paymentAddresses, paymentSplit);
    }

    function setMinStakeBatchAmount(uint256 _minStakeBatchAmount) external onlyRole(ROLE_PROTOCOL_MANAGER) {
        minStakeBatchAmount = _minStakeBatchAmount;

        emit SetMinStakeBatchAmount(_minStakeBatchAmount);
    }

    function setMinStakeAmount(uint256 _minStakeAmount) external onlyRole(ROLE_PROTOCOL_MANAGER) {
        minStakeAmount = _minStakeAmount;

        emit SetMinStakeAmount(_minStakeAmount);
    }

    function setStakePeriod(uint256 _stakePeriod) external onlyRole(ROLE_PROTOCOL_MANAGER) {
        stakePeriod = _stakePeriod;

        emit SetStakePeriod(_stakePeriod);
    }

    function setMaxUnstakeRequests(uint8 _maxUnstakeRequests) external onlyRole(ROLE_PROTOCOL_MANAGER) {
        maxUnstakeRequests = _maxUnstakeRequests;

        emit SetMaxUnstakeRequests(_maxUnstakeRequests);
    }

    function setMaxProtocolControlledAVAX(uint256 _maxProtocolControlledAVAX) external onlyRole(ROLE_PROTOCOL_MANAGER) {
        maxProtocolControlledAVAX = _maxProtocolControlledAVAX;

        emit SetMaxProtocolControlledAVAX(_maxProtocolControlledAVAX);
    }

    function setPChainExportBuffer(uint256 _pChainExportBuffer) external onlyRole(ROLE_PROTOCOL_MANAGER) {
        pChainExportBuffer = _pChainExportBuffer;
    }

    function setMinClaimWaitTimeSeconds(uint64 _minimumClaimWaitTimeSeconds) external onlyRole(ROLE_PROTOCOL_MANAGER) {
        if (_minimumClaimWaitTimeSeconds > stakePeriod) revert InvalidConfiguration();
        minimumClaimWaitTimeSeconds = _minimumClaimWaitTimeSeconds;
    }

    // -------------------------------------------------------------------------
    // Overrides
    // -------------------------------------------------------------------------

    // Necessary overrides to handle conflict between `Context` and `ContextUpgradeable`.

    function _msgSender() internal view override(Context, ContextUpgradeable) returns (address) {
        return Context._msgSender();
    }

    function _msgData() internal view override(Context, ContextUpgradeable) returns (bytes calldata) {
        return Context._msgData();
    }
}

contract PayableAvaLido is AvaLido {
    receive() external payable {}
}
