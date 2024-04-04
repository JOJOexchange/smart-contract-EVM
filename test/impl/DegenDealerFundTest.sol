/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "../init/TradingInit.sol";
import "../utils/Checkers.sol";
import "../../src/DegenDepositHelper.sol";

contract DegenFundTest is Checkers {
    function testDegenDeposit() public {
        vm.startPrank(traders[0]);
        usdc.approve(address(degenDealer), 1000e6);
        degenDealer.deposit(traders[0], traders[0], 1000e6);
        assertEq(usdc.balanceOf(address(degenDealer)), 1000e6);
    }

    function testDegenWithdraw() public {
        vm.startPrank(traders[0]);
        usdc.approve(address(degenDealer), 1000e6);
        degenDealer.deposit(traders[0], traders[0], 1000e6);
        vm.stopPrank();

        degenDealer.withdraw(traders[0], 500e6, 1, false);
        degenDealer.withdraw(traders[0], 500e6, 2, true);
        checkCredit(traders[0], 500e6, 0);
    }

    function testFastWithdrawAndRevert() public {
        DegenDepositHelper degenDepositHelper = new DegenDepositHelper(address(usdc), address(degenDealer));
        jojoDealer.setWithdrawlWhitelist(address(degenDepositHelper), true);
        degenDepositHelper.setWhiteList(address(jojoDealer), true);
        vm.startPrank(traders[0]);
        jojoDealer.deposit(1000e6, 0, traders[0]);
        jojoDealer.fastWithdraw(
            traders[0],
            address(degenDepositHelper),
            1000e6,
            0,
            false,
            abi.encodeWithSignature("depositToDegenDealer(address)", traders[0])
        );
        vm.stopPrank();
    }
}
