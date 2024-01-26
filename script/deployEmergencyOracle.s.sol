/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0*/
pragma solidity ^0.8.9;

import "forge-std/Script.sol";
import "../src/oracle/EmergencyOracle.sol";

contract EmergencyOracleScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new EmergencyOracle("WSTETH/USDC");
        vm.stopBroadcast();
    }
}
