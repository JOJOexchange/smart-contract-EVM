// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Script.sol";
import "../src/support/MockSwap.sol";
import "forge-std/Test.sol";

contract SupportsDODOScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new MockSwap(
            // USDC
            0x834D14F87700e5fFc084e732c7381673133cdbcC,
            // eth
            0x85CB137033DffD36B7B32048C2Ec42cf39cf2ee5,
            // price
            0x998bBdACf6BD51492301207a8A98B1FF8f2E0EE5
        );
        console2.log("deploy JUSD");
        vm.stopBroadcast();
    }
}
