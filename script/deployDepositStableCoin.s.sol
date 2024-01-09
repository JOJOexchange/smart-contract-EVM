// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.20;

import "../lib/forge-std/src/Script.sol";
import "../src/DepositStableCoinToDealer.sol";

contract DepositStableCoinToDealerScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new DepositStableCoinToDealer(
            //_JOJODealer
            0xFfD3B82971dAbccb3219d16b6EB2DB134bf55300,
            //_USDC
            0x834D14F87700e5fFc084e732c7381673133cdbcC,
            //_WETH
            0x85CB137033DffD36B7B32048C2Ec42cf39cf2ee5
        );
        vm.stopBroadcast();
    }
}
