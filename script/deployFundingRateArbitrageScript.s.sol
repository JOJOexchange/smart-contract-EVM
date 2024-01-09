// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/FundingRateArbitrage.sol";

contract FundingRateArbitrageScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new FundingRateArbitrage(
            //collateral
            0x85CB137033DffD36B7B32048C2Ec42cf39cf2ee5,
            //bank
            0xb0D9Ce393f3483449be357EF715a3492858f8a5E,
            //dealer
            0xFfD3B82971dAbccb3219d16b6EB2DB134bf55300,
            //perpmarket
            0xFeAdd00ac346468B30AB59b964Be060Da7272dC6,
            //operator
            0xF1D7Ac5Fd1b806d24bCd2764C7c29A9fAd51698B
        );
        vm.stopBroadcast();
    }
}
