// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/oracle/OracleAdaptor.sol";

contract OracleAdaptorScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new OracleAdaptor(
            // source
            0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F,
            // decimalCorrection
            10,
            //heartbeatInterval
            86_400,
            86_400,
            // usdc
            0x7e860098F58bBFC8648a4311b374B1D669a2bc6B,
            5e16
        );
        vm.stopBroadcast();
    }
}
