// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../lib/forge-std/src/Script.sol";
import "../src/support/BatchTransferERC20.sol";
import "../lib/forge-std/src/Test.sol";

contract BatchTransferERC20Script is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new BatchTransferERC20();
        console2.log("deploy BatchTransferERC20");
        vm.stopBroadcast();
    }
}
