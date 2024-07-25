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
            0x57fcb53c74dc2f33032c78952da7594f2ccaf3c58e4ad5fd32ab524234a0bc11,
            // timestamp
            1_724_500_800
        );
        vm.stopBroadcast();
    }
}
