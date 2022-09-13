// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

/**
 * @notice stAVAX tokens are liquid staked AVAX tokens.
 * @dev ERC-20 implementation of a non-rebasing token.
 * This contract is abstract, and must be implemented by something which
 * knows the total amount of controlled AVAX.
 */
abstract contract stAVAX is ERC20Upgradeable {
    /**
     * @notice Converts an amount of stAVAX to its equivalent in AVAX.
     * @param totalControlled The amount of AVAX controlled by the protocol.
     * @param stAvaxAmount The amount of stAVAX to convert.
     * @return Equivalent AVAX at current protocol exchange rate.
     */
    function stAVAXToAVAX(uint256 totalControlled, uint256 stAvaxAmount) public view returns (uint256) {
        if (totalSupply() == 0) {
            return 0;
        }
        if (totalControlled == 0) {
            return stAvaxAmount;
        }

        // Prevent exchange rate from rounding to zero.
        uint256 avaxAmount = Math.mulDiv(stAvaxAmount, totalControlled, totalSupply());
        if (avaxAmount == 0) {
            return 1 wei;
        }
        return avaxAmount;
    }

    /**
     * @notice Converts an amount of AVAX to its equivalent in stAVAX.
     * @param totalControlled The amount of AVAX controlled by the protocol.
     * @param avaxAmount The amount of AVAX to convert.
     * @return Equivalent stAVAX at current protocol exchange rate.
     */
    function avaxToStAVAX(uint256 totalControlled, uint256 avaxAmount) public view returns (uint256) {
        // The result is always 1:1 on the first deposit.
        if (totalSupply() == 0 || totalControlled == 0) {
            return avaxAmount;
        }

        // Prevent exchange rate from rounding to zero.
        uint256 stAVAXAmount = Math.mulDiv(avaxAmount, totalSupply(), totalControlled);
        if (stAVAXAmount == 0) {
            return 1 wei;
        }
        return stAVAXAmount;
    }

    /**
     * @dev The total protocol controlled AVAX. Must be implemented by the
     * owning contract.
     * @return amount protocol controlled AVAX
     */
    function protocolControlledAVAX() public view virtual returns (uint256);
}
