// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

interface IMpcManager {
    struct KeyInfo {
        bytes32 groupId;
        bool confirmed;
    }

    function requestStake(
        string calldata nodeID,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    ) external payable;

    function setAvaLidoAddress(address avaLidoAddress) external;

    function createGroup(bytes[] calldata publicKeys, uint256 threshold) external;

    function requestKeygen(bytes32 groupId) external;

    function getGroup(bytes32 groupId) external view returns (bytes[] memory participants, uint256 threshold);

    function getKey(bytes calldata publicKey) external view returns (KeyInfo memory keyInfo);
}
