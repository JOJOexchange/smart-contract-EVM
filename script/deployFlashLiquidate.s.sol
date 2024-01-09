// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/FlashLoanLiquidate.sol";

contract FlashLiquidateScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new FlashLoanLiquidate(
            // jusdBank
            0xb0D9Ce393f3483449be357EF715a3492858f8a5E,
            // jusdExchange
            0x33a317a875Bc23af2E083555E5E46e3ac559C40A,
            // _USDC
            0x834D14F87700e5fFc084e732c7381673133cdbcC,
            // _JUSD
            0xDd29a69462a08006Fda068D090b44B045958C5B7,
            // _insurance
            0x81c438F53Aeb554db3310104535Ab60967d78059
        );
        vm.stopBroadcast();
    }
}
