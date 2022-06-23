// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

// Test support
import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../test/helpers.sol";

// Contracts for deploy
import "../OracleManager.sol";
import "../Oracle.sol";
import "../AvaLido.sol";

contract Deploy is DSTest, Helpers {
    // Role details
    // TODO: This should be divided into roles rather than used for everything
    address admin = 0x27F957c465214d9C3AF0bf10e52e68bd839c66d4;

    // Address constants
    address lidoFeeAddress = 0x2000000000000000000000000000000000000001;
    address authorFeeAddress = 0x2000000000000000000000000000000000000002;

    // Constants
    string[] validatorAllowlist = [
        "NodeID-P7oB2McjBGgW2NXXWVYjV8JEDFoW9xDE5",
        "NodeID-GWPcbFJZFfZreETSoWjPimr846mXEKCtu",
        "NodeID-NFBbbJ4qCmNaCzeW7sxErhvWqvEQMnYcN"
    ];
    address[] oracleAllowlist = [
        0x03C1196617387899390d3a98fdBdfD407121BB67,
        0x6C58f6E7DB68D9F75F2E417aCbB67e7Dd4e413bf,
        0xa7bB9405eAF98f36e2683Ba7F36828e260BD0018,
        0xE339767906891bEE026285803DA8d8F2f346842C,
        0x0309a747a34befD1625b5dcae0B00625FAa30460
    ];

    // Deploy contracts
    // Usage: forge script src/deploy/Deploy.t.sol --sig "deploy()" --broadcast --rpc-url <PRC URL> --private-key <PK>
    // Syntax is identical to `cast`
    function deploy() public {
        // Create a transaction
        cheats.startBroadcast();

        // MPC manager
        MpcManager _mpcManager = new MpcManager();
        MpcManager mpcManager = MpcManager(address(proxyWrapped(address(_mpcManager), admin)));
        mpcManager.initialize();
        console.log("MPC Manager", address(mpcManager));

        // Oracle manager
        OracleManager _oracleManager = new OracleManager();
        OracleManager oracleManager = OracleManager(address(proxyWrapped(address(_oracleManager), admin)));
        oracleManager.initialize(admin, validatorAllowlist, oracleAllowlist);

        // Oracle
        Oracle _oracle = new Oracle();
        Oracle oracle = Oracle(address(proxyWrapped(address(_oracle), admin)));
        oracle.initialize(admin, address(oracleManager));

        // Validator selector
        ValidatorSelector _validatorSelector = new ValidatorSelector();
        ValidatorSelector validatorSelector = ValidatorSelector(
            address(proxyWrapped(address(_validatorSelector), admin))
        );
        validatorSelector.initialize(address(oracle));

        // AvaLido
        AvaLido _lido = new AvaLido();
        AvaLido lido = AvaLido(address(proxyWrapped(address(_lido), admin)));
        lido.initialize(lidoFeeAddress, authorFeeAddress, address(validatorSelector), address(mpcManager));

        cheats.stopBroadcast();
    }
}
