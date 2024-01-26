/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity ^0.8.9;

import "forge-std/Script.sol";
import "../src/support/HelperContract.sol";

contract HelperContractScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new HelperContract(
            //dealer
            0xFfD3B82971dAbccb3219d16b6EB2DB134bf55300,
            // bank
            0xb0D9Ce393f3483449be357EF715a3492858f8a5E,
            //fundingRateHedging
            0x0Cc6c0c32C074Df9D9D0b92c9d9323cA74e83bc2
        );
        console2.log("deploy HelperContract");
        vm.stopBroadcast();
    }
}
