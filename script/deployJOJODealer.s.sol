// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.20;

import "../lib/forge-std/src/Script.sol";
import "../src/JOJODealer.sol";

contract JOJODealerScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new JOJODealer(0x834D14F87700e5fFc084e732c7381673133cdbcC);
        vm.stopBroadcast();
    }
}
