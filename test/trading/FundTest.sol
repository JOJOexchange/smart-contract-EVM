/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.9;

import "../init/TradingInit.sol";
import "../utils/Checkers.sol";

contract FundTest is Checkers {


    function testDeposit() public {
        vm.startPrank(traders[0]);
        jojoDealer.deposit(100000e6, 500000e6, traders[0]);
        checkCredit(traders[0], 100000e6, 500000e6);
        assertEq(usdc.balanceOf(traders[0]), 900000e6);
        assertEq(usdc.balanceOf(address(jojoDealer)), 100000e6);
        assertEq(jusd.balanceOf(traders[0]), 500000e6);
        assertEq(jusd.balanceOf(address(jojoDealer)), 500000e6);
    }

    function testWithdrawWithTimelock() public {
        jojoDealer.setWithdrawTimeLock(100);
        vm.startPrank(traders[0]);
        jojoDealer.deposit(100000e6, 100000e6, traders[0]);
        jojoDealer.requestWithdraw(traders[0], 30000e6, 20000e6);
        checkCredit(traders[0], 100000e6, 100000e6);
        assertEq(usdc.balanceOf(traders[0]), 900000e6);
        assertEq(jusd.balanceOf(traders[0]), 900000e6);
    }

    function testWithdrawToNegative() public {
        vm.startPrank(traders[0]);
        jojoDealer.deposit(0, 1000000e6, traders[0]);
        vm.stopPrank();
        vm.startPrank(traders[1]);
        jojoDealer.deposit(1000000e6, 0, traders[1]);
        trade(100e18, -3000000e6, -100e18, 3000000e6);
        vm.stopPrank();

    }



    // function testOtherRevertCases() public {
    //     TestERC20 usdw = new TestERC20("USDW", "USDW", 12);
    //     cheats.expectRevert("JOJO_SECONDARY_ASSET_ALREADY_EXIST");
    //     jojoDealer.setSecondaryAsset(address(usdw));
    // }
}
