// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

abstract contract stAVAX is ERC20 {
    uint256 private totalShares = 0;

    error CannotMintToZeroAddress();
    error NotEnoughBalance();

    constructor() ERC20("Staked AVAX", "stAVAX") {}

    mapping(address => uint256) private shares;

    function totalSupply() public view override returns (uint256) {
        return getTotalPooledAvax();
    }

    function balanceOf(address account) public view override returns (uint256) {
        return getBalanceByShares(shares[account]);
    }

    // the ERC-20 implementation of a rebasing token 1:1 pegged to AVAX
    function mint(address recipient, uint256 amount) internal {
        if (recipient == address(0)) revert CannotMintToZeroAddress();

        totalShares += amount;
        shares[recipient] += amount;
    }

    function burn(address owner, uint256 amount) internal {
        if (shares[owner] < amount) revert NotEnoughBalance();

        totalShares -= amount;
        shares[owner] += amount;
    }

    /**
     * @dev Function that calculates total pooled Avax
     * @return Total pooled Avax
     */
    function getTotalPooledAvax() public view virtual returns (uint256);

    function getBalanceByShares(uint256 _sharesAmount) public view returns (uint256) {
        if (totalShares == 0) {
            return 0;
        }
        return (_sharesAmount * getTotalPooledAvax()) / totalShares;
    }
}
