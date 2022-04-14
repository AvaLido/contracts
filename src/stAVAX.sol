// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/**
 * @notice stAVAX tokens are liquid staked AVAX tokens.
 * @dev ERC-20 implementation of a rebasing token 1:1 pegged to AVAX.
 * This contract is abstract, and must be implemented by something which
 * knows the total amount of controlled AVAX.
 * TODO: Transfers, approvals, events.
 */
abstract contract stAVAX is ERC20 {
    uint256 private totalShares = 0;

    error CannotMintToZeroAddress();
    error NotEnoughBalance();

    constructor() ERC20("Staked AVAX", "stAVAX") {}

    mapping(address => uint256) private shares;

    /**
     * @notice The total supply of stAVAX tokens
     * @dev Because we are 1:1 with AVAX, this is simply the amount of
     * AVAX that the protocol controls.
     */
    function totalSupply() public view override returns (uint256) {
        return getProtocolControlledAVAX();
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
        if (shares[owner] < amount) revert NotEnoughBalance();

        totalShares -= amount;
        shares[owner] += amount;
    }

    /**
     * @dev The total protocol controlled AVAX. Must be implemented by the
     * owning contract.
     * @return amount protocol controlled AVAX
     */
    function getProtocolControlledAVAX() public view virtual returns (uint256);

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
        return (sharesAmount * getProtocolControlledAVAX()) / totalShares;
    }
}
