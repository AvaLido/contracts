// SPDX-FileCopyrightText: 2022 Hyperelliptic Labs and RockX
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

// Added so that slither can parse this file correctly.
interface Empty {

}

struct UnstakeRequest {
    address requester; // The user who requested the unstake.
    uint64 requestedAt; // The block.timestamp when the unstake request was made.
    uint256 amountRequested; // The amount of AVAX equal to the stAVAX the user had at request time.
    uint256 amountFilled; // The amount of free'd AVAX that has been allocated to this request.
    uint256 amountClaimed; // The amount of AVAX that has been claimed by the requester.
    uint256 stAVAXLocked; // The amount of stAVAX requested to be unstaked.
}

type Validator is uint24;

// Total 24 bits
// [ u s i i i i i i i i i i i i i i v v v v v v v v v v ]
// u = 1 bit - Does the validator have acceptible uptime?
// s = 1 bit - Does the validator have more time remaining than our largest stake period?
// i = 12 bits - index of node ID in list.
// v = 10 bits - number of 'hundreds of free avax, rounded down', capped at 256

library ValidatorHelpers {
    function hasAcceptableUptime(Validator data) public pure returns (bool) {
        uint24 shifted = Validator.unwrap(data) >> 23;
        uint24 flag = shifted & 1;
        return flag == 1 ? true : false;
    }

    function hasTimeRemaining(Validator data) public pure returns (bool) {
        // Data now has first 2 bits in lowest position.
        uint24 shifted = Validator.unwrap(data) >> 22;
        uint24 flag = shifted & 1;
        return flag == 1 ? true : false;
    }

    function getNodeIndex(Validator data) public pure returns (uint256) {
        // Take 12 bits from the middle which represents our index.
        uint24 value = Validator.unwrap(data) & 4193280; // 001111111111110000000000
        // Shift right 10 places to align
        uint24 shifted = value >> 10;
        return uint256(shifted);
    }

    function freeSpace(Validator data) public pure returns (uint256) {
        // Take the last 10 bits. Already aligned so no need to shift.
        uint24 hundredsOfAVAX = Validator.unwrap(data) & 1023; // 000000000000001111111111
        // Multiply out into Wei
        return uint256(hundredsOfAVAX) * 100 ether;
    }

    function packValidator(
        uint24 nodeIndex,
        bool hasUptime,
        bool hasSpace,
        uint24 hundredsOfAvax
    ) public pure returns (Validator) {
        assert(nodeIndex < 4096);
        assert(hundredsOfAvax < 1024);

        uint24 data = hundredsOfAvax;
        if (hasUptime) {
            data = data | (1 << 23);
        }
        if (hasSpace) {
            data = data | (1 << 22);
        }
        data = data | (nodeIndex << 10);
        return Validator.wrap(data);
    }
}
