// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

import "forge-std/console2.sol";

/**
 * @notice stAVAX tokens are liquid staked AVAX tokens.
 * @dev ERC-20 implementation of a non-rebasing token.
 * This contract is abstract, and must be implemented by something which
 * knows the total amount of controlled AVAX.
 */
abstract contract stAVAX is ERC20Upgradeable {
    /**
     * @notice Converts an amount of stAVAX to its equivalent in AVAX.
     * @dev We multiply and then divide by 1 ether (1e18) to avoid rounding errors.
     * @param totalControlled The amount of AVAX controlled by the protocol.
     * @param stAvaxAmount The amount of stAVAX to convert.
     * @return UnstakeRequest Its amount of equivalent AVAX.
     */
    function stAVAXToAVAX(uint256 totalControlled, uint256 stAvaxAmount) public view returns (uint256) {
        if (totalSupply() == 0) {
            return 0;
        }
        if (totalControlled == 0) {
            return stAvaxAmount;
        }
        return (stAvaxAmount * totalControlled * 1 ether) / totalSupply() / 1 ether;
    }

    /**
     * @notice Converts an amount of AVAX to its equivalent in stAVAX.
     * @dev We multiply and then divide by 1 ether (1e18) to avoid rounding errors.
     * @param totalControlled The amount of AVAX controlled by the protocol.
     * @param avaxAmount The amount of AVAX to convert.
     * @return UnstakeRequest Its equivalent amount of stAVAX.
     */
    function avaxToStAVAX(uint256 totalControlled, uint256 avaxAmount) public view returns (uint256) {
        console2.log("totalcontrolled");
        console2.log(totalControlled);
        // The result is always 1:1 on the first deposit.
        if (totalSupply() == 0 || totalControlled == 0) {
            return avaxAmount;
        }
        uint256 supply = totalSupply();
        console2.log("total supply of stavax");
        console2.log(supply);
        return (avaxAmount * totalSupply() * 1 ether) / totalControlled / 1 ether;
    }

    /**
     * @dev The total protocol controlled AVAX. Must be implemented by the
     * owning contract.
     * @return amount protocol controlled AVAX
     */
    function protocolControlledAVAX() public view virtual returns (uint256);
}
