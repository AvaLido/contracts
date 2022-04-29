// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/utils/Strings.sol";

import "../ValidatorManager.sol";

import "./cheats.sol";

address constant ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;
address constant USER1_ADDRESS = 0x0000000000000000000000000000000000000001;
address constant USER2_ADDRESS = 0x0000000000000000000000000000000000000002;

abstract contract Helpers {
    function validatorSelectMock(
        address manager,
        string memory node,
        uint256 amount,
        uint256 remaining
    ) public {
        string[] memory idResult = new string[](1);
        idResult[0] = node;

        uint256[] memory amountResult = new uint256[](1);
        amountResult[0] = amount;

        cheats.mockCall(
            manager,
            abi.encodeWithSelector(ValidatorManager.selectValidatorsForStake.selector),
            abi.encode(idResult, amountResult, remaining)
        );
    }

    function timeFromNow(uint256 time) public view returns (uint64) {
        return uint64(block.timestamp + time);
    }

    // TODO: Some left-padding or similar to match real-world node IDs would be nice.
    function nodeId(uint256 num) public pure returns (string memory) {
        return string(abi.encodePacked("NodeID-", Strings.toString(num)));
    }

    function nValidatorsWithInitialAndStake(
        uint256 n,
        uint256 stake,
        uint256 full,
        uint64 endTime
    ) public pure returns (Validator[] memory) {
        Validator[] memory result = new Validator[](n);
        for (uint256 i = 0; i < n; i++) {
            result[i] = Validator(endTime, stake, full, nodeId(i));
        }
        return result;
    }

    function mixOfBigAndSmallValidators() public view returns (Validator[] memory) {
        Validator[] memory smallValidators = nValidatorsWithInitialAndStake(7, 0.1 ether, 0, timeFromNow(30 days));
        Validator[] memory bigValidators = nValidatorsWithInitialAndStake(7, 100 ether, 0, timeFromNow(30 days));

        Validator[] memory validators = new Validator[](smallValidators.length + bigValidators.length);

        for (uint256 i = 0; i < smallValidators.length; i++) {
            validators[i] = smallValidators[i];
        }
        for (uint256 i = 0; i < bigValidators.length; i++) {
            validators[smallValidators.length + i] = bigValidators[i];
        }

        return validators;
    }
}
