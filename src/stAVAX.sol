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
    error CannotApproveZeroAddress();
    error InsufficientSTAVAXBalance();
    error InsufficientSTAVAXAllowance();

    // Explicit type representing shares, to add safety when moving between shares and tokens.
    type Shares256 is uint256;

    constructor() ERC20("Staked AVAX", "stAVAX") {}

    mapping(address => uint256) private shares;
    mapping(address => mapping(address => uint256)) private allowances;

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
        if (recipient == address(0)) revert CannotMintToZeroAddress();

        uint256 rawSharesAmount = Shares256.unwrap(sharesAmount);

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
     * @dev See {IERC20-transfer}.
     */
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = msg.sender;
        _transfer(owner, to, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = msg.sender;
        _approve(owner, spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @dev Transfer your stAVAX to another account.
     * Emits a {Transfer} event.
     * @param amount The amount of stAVAX to send, denominated in tokens, not shares.
     */
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        Shares256 sharesAmount = getSharesByAmount(amount);
        _transferShares(from, to, sharesAmount);
        emit Transfer(from, to, amount);
    }

    /**
     * @dev Sets `amount` in stAVAX, converted to shares, as the allowance of `spender` over `owner`'s tokens.
     * Bypasses amount conversion if allowance has been set to "infinite" (max int).
     * Emits an {Approval} event.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal override {
        if (owner == address(0) || spender == address(0)) revert CannotApproveZeroAddress();

        if (amount == type(uint256).max) {
            allowances[owner][spender] = type(uint256).max;
        } else {
            allowances[owner][spender] = Shares256.unwrap(getSharesByAmount(amount)); // Allowance in shares
        }
        emit Approval(owner, spender, amount); // Event in stAVAX
    }

    /**
     * @dev Updates `owner`'s allowance for `spender` based on spent `amount`.
     * Doesn't update allowance if it's been set to "infinite" (max int).
     */
    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal override {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            Shares256 sharesAmount = getSharesByAmount(amount);
            uint256 rawSharesAmount = Shares256.unwrap(sharesAmount);

            if (currentAllowance < rawSharesAmount) revert InsufficientSTAVAXAllowance();
            _approve(owner, spender, currentAllowance - rawSharesAmount);
        }
    }

    /**
     * @dev Transfer shares in the allocation from one address to another.
     * Note that you should use `transfer` instead if possible. Only use this when
     * calling from a nonReentrant function.
     * @param sharesAmount The number of shares to send.
     */
    function _transferShares(
        address sender,
        address recipient,
        Shares256 sharesAmount
    ) internal {
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
    function _getSharesByAmount(uint256 amount, bool excludeAmount) private view returns (Shares256) {
        // `totalShares` is 0: this is the first ever deposit. Assume that shares correspond to AVAX 1-to-1.
        if (totalShares == 0) return Shares256.wrap(amount);
        if (amount == 0) return Shares256.wrap(0);

        uint256 total = protocolControlledAVAX();
        if (excludeAmount) {
            total -= amount;
        }
        return Shares256.wrap((amount * totalShares) / total);
    }

    /**
     * @dev Public-facing version of this method, to calculate the value in shares before deposit.
     * This is the default case, for use in withdrawals, claims, and for display in the web UI.
     * @param amount amount of AVAX
     */
    function getSharesByAmount(uint256 amount) public view returns (Shares256) {
        return _getSharesByAmount(amount, false);
    }

    /**
     * @dev Computes the total amount of shares represented by a number of AVAX, excluding the
     * amount itself from share calculations, on the basis that it has already been deposited.
     * @param amount amount of AVAX
     */
    function _getDepositSharesByAmount(uint256 amount) internal view returns (Shares256) {
        return _getSharesByAmount(amount, true);
    }
}
