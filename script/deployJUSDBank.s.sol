// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/JUSDBank.sol";

contract JUSDBankScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new JUSDBank(
            // maxReservesAmount_
            10,
            // _insurance
            0x82e8F8AAf6baCa951f7aF36c37d15eFD6a0575BB,
            // JUSD
            0xDd29a69462a08006Fda068D090b44B045958C5B7,
            // JOJODealer
            0xFfD3B82971dAbccb3219d16b6EB2DB134bf55300,
            // maxBorrowAmountPerAccount_
            100_000_000_000,
            // maxBorrowAmount_
            1_000_000_000_000,
            // borrowFeeRate_
            0,
            // usdc
            0x834D14F87700e5fFc084e732c7381673133cdbcC
        );
        vm.stopBroadcast();
    }
}
