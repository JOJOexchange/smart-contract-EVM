// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/JUSDExchange.sol";

contract JUSDExchangeScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new JUSDExchange(
            // _USDC
            0x834D14F87700e5fFc084e732c7381673133cdbcC,
            // _JUSD
            0xDd29a69462a08006Fda068D090b44B045958C5B7
        );
        vm.stopBroadcast();
    }
}
