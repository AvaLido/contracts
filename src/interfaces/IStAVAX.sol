// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

interface IStAVAX is IERC20 {
    // Todo: I think getBalanceByShares needs to be made public?
    function getBalanceByShares(Shares256 sharesAmount) external view returns (uint256);

    function getSharesByAmount(uint256 amount) external view returns (uint256);
}
