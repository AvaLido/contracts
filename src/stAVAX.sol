// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract stAVAX is ERC20 {
    constructor() ERC20("Staked AVAX", "stAVAX") {}

    // the ERC-20 implementation of a rebasing token 1:1 pegged to AVAX
    function mint() public {}

    function burn() public {}

    // Note: does this stuff need to be in the main contract as helpers?

    /**
     * @dev Function that calculates total pooled Avax
     * @return Total pooled Avax
     */
    function gettotalPooledAvax() public view returns (uint256) {
        // uint256 totalStaked = // need to figure this out from oracle contract
        // return totalStaked + totalBuffered - reservedFunds;
        return 0;
    }

    /**
     * @dev Function that converts arbitrary Avax to stAVAX
     * @param _balance - Balance in Avax
     * @return Balance in stAVAX, totalShares and totalPooledAvax
     */
    function convertAvaxToStAvax(uint256 _balance)
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 totalShares = totalSupply();
        // If total supply is 0 (i.e. first person depositing) then totalShares is 1 bc they have it all
        totalShares = totalShares == 0 ? 1 : totalShares;

        uint256 totalPooledAvax = gettotalPooledAvax();
        totalPooledAvax = totalPooledAvax == 0 ? 1 : totalPooledAvax;

        uint256 balanceInStAvax = (_balance * totalShares) / totalPooledAvax;

        return (balanceInStAvax, totalShares, totalPooledAvax);
    }

    /**
     * @dev Function that converts arbitrary stAVAX to Avax
     * @param _balance - Balance in stAVAX
     * @return Balance in Avax, totalShares and totalPooledAvax
     */
    function convertStAvaxToAvax(uint256 _balance)
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 totalShares = totalSupply();
        totalShares = totalShares == 0 ? 1 : totalShares;

        uint256 totalPooledAvax = gettotalPooledAvax();
        totalPooledAvax = totalPooledAvax == 0 ? 1 : totalPooledAvax;

        uint256 balanceInAvax = (_balance * totalPooledAvax) / totalShares;

        return (balanceInAvax, totalShares, totalPooledAvax);
    }
}
