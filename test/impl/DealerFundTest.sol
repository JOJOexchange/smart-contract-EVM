/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../../src/DepositStableCoinToDealer.sol";
import "../init/TradingInit.sol";
import "../utils/Checkers.sol";

// Check dealer's deposit/withdraw
contract FundTest is Checkers {
    function testDeposit() public {
        vm.startPrank(traders[0]);
        jojoDealer.deposit(100_000e6, 500_000e6, traders[0]);
        checkCredit(traders[0], 100_000e6, 500_000e6);
        assertEq(usdc.balanceOf(traders[0]), 900_000e6);
        assertEq(usdc.balanceOf(address(jojoDealer)), 100_000e6);
        assertEq(jusd.balanceOf(traders[0]), 500_000e6);
        assertEq(jusd.balanceOf(address(jojoDealer)), 500_000e6);
    }

    function testWithdrawWithTimelock() public {
        jojoDealer.setWithdrawTimeLock(100);
        vm.startPrank(traders[0]);
        jojoDealer.deposit(100_000e6, 100_000e6, traders[0]);
        jojoDealer.requestWithdraw(traders[0], 30_000e6, 20_000e6);
        checkCredit(traders[0], 100_000e6, 100_000e6);
        assertEq(usdc.balanceOf(traders[0]), 900_000e6);
        assertEq(jusd.balanceOf(traders[0]), 900_000e6);
    }

    function testWithdrawToNegative() public {
        vm.startPrank(traders[0]);
        jojoDealer.deposit(0, 1_000_000e6, traders[0]);
        vm.stopPrank();
        vm.startPrank(traders[1]);
        jojoDealer.deposit(1_000_000e6, 0, traders[1]);
        vm.stopPrank();
        trade(100e18, -3_000_000e6, -100e18, 3_000_000e6, 100e18, 100e18, address(perpList[0]));
        priceSourceList[0].setMarkPrice(30_100e6);

        vm.startPrank(traders[1]);
        cheats.expectRevert("JOJO_WITHDRAW_INVALID");
        jojoDealer.requestWithdraw(traders[0], 1000e6, 0);
        vm.stopPrank();
        vm.startPrank(traders[0]);
        jojoDealer.requestWithdraw(traders[0], 1000e6, 0);
        vm.stopPrank();
        vm.startPrank(traders[1]);
        cheats.expectRevert("JOJO_WITHDRAW_INVALID");
        jojoDealer.executeWithdraw(traders[0], traders[0], false, "");
        vm.stopPrank();
        vm.startPrank(traders[0]);
        jojoDealer.executeWithdraw(traders[0], traders[0], false, "");
        checkCredit(traders[0], -1000e6, 1_000_000e6);
        jojoDealer.requestWithdraw(traders[0], 0, 990_000e6);
        cheats.expectRevert("JOJO_ACCOUNT_NOT_SAFE");
        jojoDealer.executeWithdraw(traders[0], traders[0], false, "");
    }

    function testWithdrawInternalTransfer() public {
        jojoDealer.setWithdrawTimeLock(10);
        vm.startPrank(traders[0]);
        jojoDealer.deposit(1_000_000e6, 1_000_000e6, traders[0]);
        jojoDealer.requestWithdraw(traders[0], 500_000e6, 200_000e6);
        cheats.expectRevert("JOJO_WITHDRAW_PENDING");
        jojoDealer.executeWithdraw(traders[0], traders[1], true, "");
        vm.stopPrank();
        jojoDealer.setWithdrawTimeLock(0);
        vm.startPrank(traders[0]);
        jojoDealer.requestWithdraw(traders[0], 500_000e6, 200_000e6);
        jojoDealer.executeWithdraw(traders[0], traders[1], true, "");
        checkCredit(traders[0], 500_000e6, 800_000e6);
        checkCredit(traders[1], 500_000e6, 200_000e6);
    }

    function testOtherRevertCasesSolidSafeCheck() public {
        vm.startPrank(traders[1]);
        jojoDealer.deposit(100_000e6, 100_000e6, traders[1]);
        vm.stopPrank();
        vm.startPrank(traders[0]);
        jojoDealer.deposit(100_000e6, 100_000e6, traders[0]);
        jojoDealer.requestWithdraw(traders[0], 100_001e6, 0);
        cheats.expectRevert("JOJO_ACCOUNT_NOT_SAFE");
        jojoDealer.executeWithdraw(traders[0], traders[0], false, "");
    }

    function testOtherRevertCasesSafeCheck() public {
        vm.startPrank(traders[0]);
        jojoDealer.deposit(0, 1_000_000e6, traders[0]);
        vm.stopPrank();
        vm.startPrank(traders[1]);
        jojoDealer.deposit(1_000_000e6, 0, traders[1]);
        vm.stopPrank();
        trade(100e18, -3_000_000e6, -100e18, 3_000_000e6, 100e18, 100e18, address(perpList[0]));

        vm.startPrank(traders[0]);
        jojoDealer.requestWithdraw(traders[0], 0, 999_000e6);
        cheats.expectRevert("JOJO_ACCOUNT_NOT_SAFE");
        jojoDealer.executeWithdraw(traders[0], traders[0], false, "");
    }

    function testOtherRevertCasesRevert() public {
        vm.startPrank(traders[0]);
        jojoDealer.deposit(1_000_000e6, 1_000_000e6, traders[0]);
        jojoDealer.requestWithdraw(traders[0], 0x8000000000000000000000000000000000000000000000000000000000000000, 0x0);
        vm.warp(50);
        cheats.expectRevert("SafeCast: value doesn't fit in an int256");
        jojoDealer.executeWithdraw(traders[0], traders[0], true, "");
    }

    function testApproveOthers() public {
        vm.startPrank(traders[0]);
        jojoDealer.deposit(1_000_000e6, 1_000_000e6, traders[0]);
        jojoDealer.approveFundOperator(traders[2], 100e6, 100e6);
    }

    function testFastWithdrawAndRevert() public {
        vm.startPrank(traders[1]);
        jojoDealer.deposit(100_000e6, 100_000e6, traders[1]);
        vm.stopPrank();
        vm.startPrank(traders[0]);
        jojoDealer.deposit(100_000e6, 100_000e6, traders[0]);
        cheats.expectRevert("JOJO_WITHDRAW_INVALID");
        jojoDealer.fastWithdraw(traders[1], traders[1], 100e6, 100e6, false, "");
        jojoDealer.approveFundOperator(traders[1], 100e6, 100e6);
        vm.stopPrank();
        vm.startPrank(traders[1]);
        jojoDealer.fastWithdraw(traders[0], traders[0], 100e6, 0, false, "");
        jojoDealer.fastWithdraw(traders[0], traders[0], 0, 100e6, false, "");
        cheats.expectRevert("Ownable: caller is not the owner");
        jojoDealer.fastWithdraw(
            traders[1],
            address(jojoDealer),
            100e6,
            100e6,
            false,
            abi.encodeWithSignature("setSecondaryAsset(address)", address(jojoDealer))
        );
        cheats.expectRevert("target is not a contract");
        jojoDealer.fastWithdraw(
            traders[1],
            traders[0],
            100e6,
            100e6,
            false,
            abi.encodeWithSignature("setSecondaryAsset(address)", address(jojoDealer))
        );
        vm.stopPrank();
    }
}
