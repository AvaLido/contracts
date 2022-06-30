pragma solidity 0.8.10;

import "../interfaces/IMpcManager.sol";

uint256 constant amount = 25 ether;
uint256 constant STAKE_PERIOD = 14 days;
string constant NODE_ID = "NodeID-P7oB2McjBGgW2NXXWVYjV8JEDFoW9xDE5";

interface IMpcManagerSimple {
    function requestStake(string calldata nodeID, uint256 amount, uint256 startTime, uint256 endTime) external payable;
}

// This version of AvaLido contract is simplified for testing of MPC-Manager stake feature.
// todo: consider add deposit() function
contract MockAvaLido {
    IMpcManager public mpcManager;

    constructor(
        address _mpcManagerAddress
    ) payable {
        mpcManager = IMpcManager(_mpcManagerAddress);
    }

    receive() payable external {
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function initiateStake() external returns (uint256) {
        uint256 startTime = block.timestamp + 30 seconds;
        uint256 endTime = startTime + STAKE_PERIOD;
        mpcManager.requestStake{value: amount}(NODE_ID, amount, startTime, endTime);

        return amount;
    }
}
