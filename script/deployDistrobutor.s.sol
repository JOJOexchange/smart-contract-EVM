// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "../lib/forge-std/src/Script.sol";
import "../src/MerkleDistributorWithDeadline.sol";

contract MerkleDistributorWithDeadlineScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_BASE_TEST_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new MerkleDistributorWithDeadline(
            // token
            0xA42589C591f8AE08B0e2C2C18439d72628a66c3E,
            // root
            0xdd456584bb08073476d98226fcacbce40633adbf1b7fe4e0ad4cef1f462e98b6,
            // timestamp
            1724860800
        );
        vm.stopBroadcast();
    }
}
