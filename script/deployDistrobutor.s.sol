// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "../lib/forge-std/src/Script.sol";
import "../src/MerkleDistributorWithDeadline.sol";

contract MerkleDistributorWithDeadlineScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new MerkleDistributorWithDeadline(
            // token
            0xe98cffA80f32354517948536CDD5947bBe95108F,
            // root
            0xeb1d63298ea0b23261ab304d07f058c1ce7fd1e2f25530d90f927d931cd4b2f8,
            // timestamp
            1_705_928_400
        );
        vm.stopBroadcast();
    }
}
