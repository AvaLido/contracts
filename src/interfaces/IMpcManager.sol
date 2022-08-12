// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

interface IMpcManager {
    function requestStake(
        string calldata nodeID,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    ) external payable;

    function createGroup(bytes[] calldata publicKeys, uint8 threshold) external;

    function requestKeygen(bytes32 groupId) external;

    function cancelKeygen() external;

    function getGroup(bytes32 groupId) external view returns (bytes[] memory participants);

    function getGroupIdByKey(bytes calldata publicKey) external view returns (bytes32);
}
