// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.20;

import "../lib/forge-std/src/Script.sol";
import "../src/subaccount/BotSubaccountFactory.sol";

contract BotSubaccountFactoryScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new BotSubaccountFactory(0xFfD3B82971dAbccb3219d16b6EB2DB134bf55300, 0xF1D7Ac5Fd1b806d24bCd2764C7c29A9fAd51698B);
        vm.stopBroadcast();
    }
}
