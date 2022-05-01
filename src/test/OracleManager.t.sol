// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

// import "ds-test/src/test.sol";
import "ds-test/test.sol";
import "./cheats.sol";
import "./helpers.sol";
import "./console.sol";
import "../OracleManager.sol";

contract OracleManagerTest is DSTest, Helpers {
	OracleManager oracleManager;

    function setUp() public {
        oracleManager = new OracleManager();
    }

    function testAddOracleMember() public {
		//assertEq(oracleManager.QUORUM_THRESHOLD(), 2);
		oracleManager.addOracleMember(0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2);
		assertEq(oracleManager.oracleMembers(2), 0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2);
    }

	function testAddOracleMember() public {
		oracleManager.addOracleMember(0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2);
		assertEq(oracleManager.oracleMembers(2), 0x3e46faFf7369B90AA23fdcA9bC3dAd274c41E8E2);
    }
}
