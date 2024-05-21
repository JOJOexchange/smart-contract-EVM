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
        uint256 deployerPrivateKey = vm.envUint("JOJO_BASE_TEST_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new HelperContract(
            //dealer
            0x65bE09345311aCc72d9358Ea7d7B13A91DFF51B6,
            // bank
            0x7F8f65D24a7C4d7f7a8b8F5457c91939712479b9,
            //fundingRateHedging
            0x6beC83cAdf39E4606B82C628423F34C53B8b3109
        );
        console2.log("deploy HelperContract");
        vm.stopBroadcast();
    }
}
