// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/utils/Strings.sol";

import "../ValidatorSelector.sol";
import "../MpcManager.sol";

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
address constant MPC_PLAYER_1_ADDRESS = 0x3051bA2d313840932B7091D2e8684672496E9A4B;
address constant MPC_PLAYER_2_ADDRESS = 0x7Ac8e2083E3503bE631a0557b3f2A8543EaAdd90;
address constant MPC_PLAYER_3_ADDRESS = 0x3600323b486F115CE127758ed84F26977628EeaA;
bytes constant MPC_PLAYER_1_PUBKEY = hex"c20e0c088bb20027a77b1d23ad75058df5349c7a2bfafff7516c44c6f69aa66defafb10f0932dc5c649debab82e6c816e164c7b7ad8abbe974d15a94cd1c2937";
bytes constant MPC_PLAYER_2_PUBKEY = hex"d0639e479fa1ca8ee13fd966c216e662408ff00349068bdc9c6966c4ea10fe3e5f4d4ffc52db1898fe83742a8732e53322c178acb7113072c8dc6f82bbc00b99";
bytes constant MPC_PLAYER_3_PUBKEY = hex"73ee5cd601a19cd9bb95fe7be8b1566b73c51d3e7e375359c129b1d77bb4b3e6f06766bde6ff723360cee7f89abab428717f811f460ebf67f5186f75a9f4288d";
bytes constant MPC_GENERATED_PUBKEY = hex"c6184cd4d6e7eeadd09410fe06a30bc06355c8c8c4dabd5c1e2d3c30d6ba42386bac735d7f4e7d264ac8741ab382a7868bf1bfa3f3b74a67f83d032309d4599c";
address constant MPC_GENERATED_ADDRESS = 0x24CE57563754DBEc6a92b8bA10af2D2416C237e4;

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

    function mpcRequestStakeMock(
        address mpcManager,
        string calldata nodeID,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    ) public {
        // TODO: Use mockCall with value. Don't know why it's not available now.
        cheats.mockCall(
            mpcManager,
            abi.encodeWithSelector(MpcManager.requestStake.selector),
            abi.encode(nodeID, amount, startTime, endTime)
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
