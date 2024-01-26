// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Script.sol";
import "../src/support/TestERC20.sol";
import "forge-std/Test.sol";

contract TokenScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new TestERC20("ARB", "ARB", 18);
        console2.log("deploy ARB");
        vm.stopBroadcast();
    }
}
