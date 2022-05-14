// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/utils/Strings.sol";

import "../ValidatorSelector.sol";

import "./cheats.sol";

address constant ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;
address constant USER1_ADDRESS = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;
address constant USER2_ADDRESS = 0x220866B1A2219f40e72f5c628B65D54268cA3A9D;
address constant ROLE_ORACLE_MANAGER = 0xf195179eEaE3c8CAB499b5181721e5C57e4769b2; // Wendy the whale gets to manage the oracle 🐳
string constant WHITELISTED_VALIDATOR_1 = "NodeID-P7oB2McjBGgW2NXXWVYjV8JEDFoW9xDE5";
string constant WHITELISTED_VALIDATOR_2 = "NodeID-GWPcbFJZFfZreETSoWjPimr846mXEKCtu";
string constant WHITELISTED_VALIDATOR_3 = "NodeID-NFBbbJ4qCmNaCzeW7sxErhvWqvEQMnYcN";
address constant WHITELISTED_ORACLE_1 = 0x03C1196617387899390d3a98fdBdfD407121BB67;
address constant WHITELISTED_ORACLE_2 = 0x6C58f6E7DB68D9F75F2E417aCbB67e7Dd4e413bf;
address constant WHITELISTED_ORACLE_3 = 0xa7bB9405eAF98f36e2683Ba7F36828e260BD0018;
address constant WHITELISTED_ORACLE_4 = 0xE339767906891bEE026285803DA8d8F2f346842C;
address constant WHITELISTED_ORACLE_5 = 0x0309a747a34befD1625b5dcae0B00625FAa30460;

abstract contract Helpers {
    function validatorSelectMock(
        address validatorSelector,
        string memory node,
        uint256 amount,
        uint256 remaining
    ) public {
        string[] memory idResult = new string[](1);
        idResult[0] = node;

        uint256[] memory amountResult = new uint256[](1);
        amountResult[0] = amount;

        cheats.mockCall(
            validatorSelector,
            abi.encodeWithSelector(ValidatorSelector.selectValidatorsForStake.selector),
            abi.encode(idResult, amountResult, remaining)
        );
    }

    function stringArrayContains(string memory stringToCheck, string[] memory arrayOfStrings)
        public
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < arrayOfStrings.length; i++) {
            if (keccak256(abi.encodePacked(arrayOfStrings[i])) == keccak256(abi.encodePacked(stringToCheck))) {
                return true;
            }
        }
        return false;
    }

    function addressArrayContains(address addressToCheck, address[] memory arrayOfAddresses)
        public
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < arrayOfAddresses.length; i++) {
            if (keccak256(abi.encodePacked(arrayOfAddresses[i])) == keccak256(abi.encodePacked(addressToCheck))) {
                return true;
            }
        }
        return false;
    }
}
