// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/JUSDBank/FlashLoanLiquidate.sol";

contract FlashLiquidateScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new FlashLoanLiquidate(
            // jusdBank
            0x8Eb3E014e1D6aB354dFBd44880eb7E6b403EE3fE,
            // jusdExchange
            0x78307eaa9A30a27639f656Ead99298C065C07b66,
            // _USDC
            0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            // _JUSD
            0x0013BbB9F5d913F700B10E316768e7935D1A13d4,
            // _insurance
            0x9C9DD45db8045954309078dC5f235024bC75Cb81
        );
        vm.stopBroadcast();
    }
}
