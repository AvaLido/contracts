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
 */
abstract contract stAVAX is ERC20, ReentrancyGuard {
    uint256 private totalShares = 0;

    error CannotMintToZeroAddress();
    error CannotSendToZeroAddress();
    error InsufficientSTAVAXBalance();

    // Explicit type representing shares, to add safety when moving between shares and tokens.
    type Shares256 is uint256;

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
        Shares256 sharesAmount = Shares256.wrap(shares[account]);
        uint256 balance = getBalanceByShares(sharesAmount);
        return balance;
    }

    /**
     * @dev Mint shares to a given address.
     * This is simply the act of increasing the total supply and allocating shares
     * to the given address.
     */
    function _mintShares(address recipient, Shares256 sharesAmount) internal {
        uint256 rawSharesAmount = Shares256.unwrap(sharesAmount);

        if (recipient == address(0)) revert CannotMintToZeroAddress();

        totalShares += rawSharesAmount;
        shares[recipient] += rawSharesAmount;
    }

    /**
     * @dev Burn shares from a given address.
     */
    function _burnShares(address owner, Shares256 sharesAmount) internal {
        uint256 rawSharesAmount = Shares256.unwrap(sharesAmount);

        if (shares[owner] < rawSharesAmount) revert InsufficientSTAVAXBalance();

        totalShares -= rawSharesAmount;
        shares[owner] -= rawSharesAmount;
    }

    /**
     * @notice Transfer your stAVAX to another account.
     * @param recipient The address of the recipient.
     * @param amount The amount of stAVAX to send, denominated in tokens, not shares.
     */
    function transfer(address recipient, uint256 amount) public override nonReentrant returns (bool) {
        Shares256 sharesAmount = getSharesByAmount(amount);
        _transferShares(msg.sender, recipient, sharesAmount);
        return true;
    }

    /**
     * @dev Transfer shares in the allocation from one address to another.
     * Note that you should use `transfer` instead if possible. Only use this when
     * calling from a nonReentrant function.
     * @param sharesAmount The number of shares to send.
     */
    function _transferShares(address sender, address recipient, Shares256 sharesAmount) internal {
        if (sender == address(0) || recipient == address(0)) revert CannotSendToZeroAddress();

        uint256 currentSenderShares = shares[sender];
        uint256 rawSharesAmount = Shares256.unwrap(sharesAmount);

        if (rawSharesAmount > currentSenderShares) revert InsufficientSTAVAXBalance();

        shares[sender] = currentSenderShares -= rawSharesAmount;
        shares[recipient] = shares[recipient] += rawSharesAmount;
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
    function getBalanceByShares(Shares256 sharesAmount) private view returns (uint256) {
        uint256 rawSharesAmount = Shares256.unwrap(sharesAmount);
        if (totalShares == 0 || rawSharesAmount == 0) {
            return 0;
        }
        return (rawSharesAmount * protocolControlledAVAX()) / totalShares;
    }

    /**
     * @dev Computes the total amount of shares represented by a number of AVAX.
     * @param amount amount of AVAX
     * @param excludeAmount excludes amount from protocolControlledAVAX, for the case where deposit happens before mint
     * @return number of shares represented by AVAX
     */
    function getSharesByAmount(uint256 amount, bool excludeAmount) public view returns (Shares256) {
        if (totalShares == 0 || amount == 0) {
            return Shares256.wrap(0);
        }

        uint256 rawSharesAmount;
        if (excludeAmount) {
            rawSharesAmount = (amount * totalShares) / (protocolControlledAVAX() - amount);
        } else {
            rawSharesAmount = (amount * totalShares) / protocolControlledAVAX();
        }

        return Shares256.wrap(rawSharesAmount);
    }

    function getSharesByAmount(uint256 amount) public view returns (Shares256) {
      return getSharesByAmount(amount, false);
    }
}
