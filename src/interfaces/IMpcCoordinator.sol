// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

interface IMpcCoordinator {
    function joinRequest(uint256 requestId, uint256 myIndex) external;

    function reportGeneratedKey(
        bytes32 groupId,
        uint256 myIndex,
        bytes calldata generatedPublicKey
    ) external;
}
