// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.20;

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
            0x56a43EB56Da12C0dc1D972ACb089c06a5dEF8e69,
            // decimalCorrection
            20,
            //heartbeatInterval
            86_400,
            86_400,
            // usdc
            0x0153002d20B96532C639313c2d54c3dA09109309,
            5e16
        );
        vm.stopBroadcast();
    }
}
