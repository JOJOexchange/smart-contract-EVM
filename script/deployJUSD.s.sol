// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/token/JUSD.sol";

contract JUSDScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_OP_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new JUSD(6);
        vm.stopBroadcast();
    }
}
