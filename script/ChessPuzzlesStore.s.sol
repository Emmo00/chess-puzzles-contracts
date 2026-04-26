// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ChessPuzzlesStore} from "../src/ChessPuzzlesStore.sol";

contract ChessPuzzlesStoreScript is Script {
    function run() external returns (ChessPuzzlesStore deployed) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        address admin = vm.envAddress("STORE_ADMIN");
        address initialServer = vm.envAddress("STORE_INITIAL_SERVER");

        vm.startBroadcast(privateKey);

        deployed = new ChessPuzzlesStore(admin, initialServer);

        vm.stopBroadcast();

        console2.log("ChessPuzzlesStore deployed at:", address(deployed));
        console2.log("Admin:", admin);
        console2.log("Initial Server:", initialServer);
    }
}
