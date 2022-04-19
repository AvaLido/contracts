// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

import "./test/console.sol";

/**
 * @notice stAVAX tokens are liquid staked AVAX tokens.
 * @dev ERC-20 implementation of a rebasing token 1:1 pegged to AVAX.
 * This contract is abstract, and must be implemented by something which
 * knows the total amount of controlled AVAX.
 * TODO: Transfers, approvals, events.
 */
abstract contract stAVAX is ERC20, ReentrancyGuard {
    uint256 private totalShares = 0;

    error CannotMintToZeroAddress();
    error CannotSendToZeroAddress();
    error InsufficientSTAVAXBalance();

    constructor() ERC20("Staked AVAX", "stAVAX") {}

    mapping(address => uint256) private shares;

    /**
     * @notice The total supply of stAVAX tokens
     * @dev Because we are 1:1 with AVAX, this is simply the amount of
     * AVAX that the protocol controls.
     */
    function totalSupply() public view override returns (uint256) {
        return protocolControlledAVAX();
    }

    function balanceOf(address account) public view override returns (uint256) {
        return getBalanceByShares(shares[account]);
    }

    /**
     * @dev Mint tokens to a given address.
     * This is simply the act of increasing the total supply and allocating shares
     * to the given address.
     */
    function mint(address recipient, uint256 amount) internal {
        if (recipient == address(0)) revert CannotMintToZeroAddress();

        totalShares += amount;
        shares[recipient] += amount;
    }

    /**
     * @dev Burn tokens from a given address.
     */
    function burn(address owner, uint256 amount) internal {
        if (shares[owner] < amount) revert InsufficientSTAVAXBalance();
        totalShares -= amount;
        shares[owner] -= amount;
    }

    // TODO: Temporarily set to allow all.
    function allowance(address owner, address spender) public view override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Transfer your stAVAX to another account.
     * @param recipient The address of the recipient.
     * @param amount The amount of stAVAX to send.
     */
    function transfer(address recipient, uint256 amount) public override nonReentrant returns (bool) {
        _transferShares(msg.sender, recipient, amount);
        return true;
    }

    /**
     * @dev Transfer shares in the allocation from one address to another.
     * Note that you should use `transfer` instead if possible. Only use this when
     * calling from a nonReentrant function.
     */
    function _transferShares(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        if (sender == address(0) || recipient == address(0)) revert CannotSendToZeroAddress();

        uint256 currentSenderShares = shares[sender];
        if (amount > currentSenderShares) revert InsufficientSTAVAXBalance();

        shares[sender] = currentSenderShares -= amount;
        shares[recipient] = shares[recipient] += amount;
    }

    /**
     * @dev The total protocol controlled AVAX. Must be implemented by the
     * owning contract.
     * @return amount protocol controlled AVAX
     */
    function protocolControlledAVAX() public view virtual returns (uint256);

    /**
     * @dev Computes the total amount of AVAX represented by a number of shares.
     * Note that this can slightly underreport due to rounding down of the division.
     * @param sharesAmount number of shares
     * @return amount of AVAX represented by shares
     */
    function getBalanceByShares(uint256 sharesAmount) private view returns (uint256) {
        if (totalShares == 0 || sharesAmount == 0) {
            return 0;
        }
        return (sharesAmount * protocolControlledAVAX()) / totalShares;
    }

    /**
     * @dev Computes the total amount of shares represented by a number of AVAX.
     * @param amount amount of AVAX
     * @return number of shares represented by AVAX
     */
    function getSharesByAmount(uint256 amount) public view returns (uint256) {
        if (totalShares == 0 || amount == 0) {
            return 0;
        }
        return (amount * totalShares) / protocolControlledAVAX();
    }
}
