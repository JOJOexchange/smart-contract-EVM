// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/FundingRateArbitrage.sol";

contract FundingRateArbitrageScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_BASE_TEST_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new FundingRateArbitrage(
            //collateral
            0xdc8f523692A88E938fbab280eD6322927E39CcE8,
            //dealer
            0x65bE09345311aCc72d9358Ea7d7B13A91DFF51B6,
            //perpmarket
            0xC783678d996A480b58fdf7Fa355dead816C7DD75,
            //operator
            0xF1D7Ac5Fd1b806d24bCd2764C7c29A9fAd51698B,
            0x51E92A8109c52e1B9673539CBEF2BB8dbEd0Fb50
        );
        vm.stopBroadcast();
    }
}
