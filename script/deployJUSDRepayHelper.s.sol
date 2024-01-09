// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/JUSDRepayHelper.sol";

contract JUSDRepayHelperScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new JUSDRepayHelper(
            // _jusdBank
            0xb0D9Ce393f3483449be357EF715a3492858f8a5E,
            // _JUSD
            0xDd29a69462a08006Fda068D090b44B045958C5B7,
            //USDC
            0x834D14F87700e5fFc084e732c7381673133cdbcC,
            // jusdExchange
            0x33a317a875Bc23af2E083555E5E46e3ac559C40A
        );
        vm.stopBroadcast();
    }
}
