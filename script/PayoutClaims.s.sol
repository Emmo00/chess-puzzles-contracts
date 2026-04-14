// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {PayoutClaims} from "../src/PayoutClaims.sol";

contract PayoutClaimsScript is Script {
    function run() external returns (PayoutClaims deployed) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        address payoutToken = vm.envAddress("PAYOUT_TOKEN");
        address serverSigner = vm.envAddress("SERVER_SIGNER");
        uint256 checkInAmount = vm.envUint("CHECK_IN_AMOUNT");
        uint256 maxDailyCheckIns = vm.envUint("MAX_DAILY_CHECK_INS");
        address owner = vm.envAddress("OWNER");

        vm.startBroadcast(privateKey);

        deployed = new PayoutClaims(payoutToken, serverSigner, checkInAmount, maxDailyCheckIns, owner);

        vm.stopBroadcast();

        console2.log("PayoutClaims deployed at:", address(deployed));
        console2.log("Payout token:", payoutToken);
        console2.log("Server signer:", serverSigner);
        console2.log("Owner:", owner);
        console2.log("Check-in amount:", checkInAmount);
        console2.log("Max daily check-ins:", maxDailyCheckIns);
    }
}
