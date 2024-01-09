/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../init/JUSDBankInit.t.sol";

// Check jusdbank's withdraw
contract JUSDBankWithdrawTest is JUSDBankInitTest {
    function testWithdrawAmountIsZero() public {
        eth.transfer(alice, 10e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        cheats.expectRevert("WITHDRAW_AMOUNT_IS_ZERO");
        jusdBank.withdraw(address(eth), 0, alice, false);
    }

    function testWithdrawAmountEasy() public {
        eth.transfer(alice, 10e18);
        btc.transfer(alice, 20e8);
        btc.transfer(bob, 20e8);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        btc.approve(address(jusdBank), 20e8);
        // 10 eth 10 btc
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        jusdBank.deposit(alice, address(btc), 10e8, alice);
        jusdBank.borrow(4000e6, alice, false);
        uint256 maxToken2 = jusdBank.getMaxWithdrawAmount(address(btc), alice);
        assertEq(maxToken2, 10e8);
        // 10 btc
        jusdBank.withdraw(address(eth), 5e18, alice, false);
        vm.stopPrank();
        jusdBank.delistReserve(address(eth));
        vm.startPrank(alice);
        cheats.expectRevert("RESERVE_NOT_ALLOW_DEPOSIT");
        jusdBank.withdraw(address(eth), 5e18, alice, true);
        vm.stopPrank();
        jusdBank.relistReserve(address(eth));
        vm.startPrank(alice);
        jusdBank.withdraw(address(eth), 5e18, alice, false);
        emit log_uint(jusdBank.getDepositMaxMintAmount(alice));
        uint256 maxToken1 = jusdBank.getMaxWithdrawAmount(address(eth), alice);
        maxToken2 = jusdBank.getMaxWithdrawAmount(address(btc), alice);
        assertEq(maxToken1, 0);
        assertEq(maxToken2, 971_428_571);

        vm.stopPrank();
        vm.startPrank(bob);
        btc.approve(address(jusdBank), 20e8);
        jusdBank.deposit(bob, address(btc), 10e8, alice);
    }

    function testWithdrawWithdrawAmountIsTooBig() public {
        eth.transfer(alice, 10e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        cheats.expectRevert("WITHDRAW_AMOUNT_IS_TOO_BIG");
        jusdBank.withdraw(address(eth), 11e18, alice, false);
    }

    function testWithDrawSuccess() public {
        // eth btc
        eth.transfer(alice, 10e18);
        btc.transfer(alice, 10e8);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        btc.approve(address(jusdBank), 10e8);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        vm.warp(1000);
        jusdBank.deposit(alice, address(btc), 10e8, alice);
        vm.warp(2000);
        // max borrow amount
        jusdBank.borrow(5000e6, alice, false);
        uint256 rate = jusdBank.getTRate();
        jusd.approve(address(jusdBank), 5000e6);
        vm.warp(3000);
        jusdBank.withdraw(address(eth), 1e18, alice, false);
        // deposit 9 eth 10 btc borrow 5000
        uint256 rate2 = jusdBank.getTRate();
        uint256 maxToken2 = jusdBank.getMaxWithdrawAmount(address(btc), alice);
        uint256 maxToken1 = jusdBank.getMaxWithdrawAmount(address(eth), alice);
        emit log_uint(((8500e6 - jusdBank.getBorrowBalance(alice)) * 1e18) / ((5e17 * 800_000_000) / 1e18));
        emit log_uint((5000e6 * 1e18) / rate);
        uint256 balance = eth.balanceOf(alice);
        uint256 aliceJusd = jusdBank.getBorrowBalance(alice);
        emit log_uint(aliceJusd);
        uint256 maxMint = jusdBank.getDepositMaxMintAmount(alice);
        assertEq(balance, 1e18);
        assertEq(aliceJusd, (4_999_993_662 * rate2) / 1e18);
        assertEq(maxMint, 107_200e6);
        assertEq(maxToken2, 1_000_000_000);
        assertEq(maxToken1, 9e18);
        vm.stopPrank();
    }

    function testWithDrawlNotMax() public {
        eth.transfer(alice, 10e18);
        btc.transfer(alice, 10e8);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        btc.approve(address(jusdBank), 10e8);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        vm.warp(1000);
        jusdBank.deposit(alice, address(btc), 10e8, alice);
        vm.warp(2000);
        // max borrow amount
        jusdBank.borrow(6000e6, alice, false);
        uint256 rateT2 = jusdBank.tRate();
        jusd.approve(address(jusdBank), 6000e6);
        vm.warp(3000);
        jusdBank.repay(5000e6, alice);
        uint256 rateT3 = jusdBank.tRate();
        jusdBank.withdraw(address(eth), 5, alice, false);
        jusdBank.withdraw(address(btc), 5, alice, false);
        emit log_uint((6000e6 * 1e18) / rateT2 + 1 - (5000e6 * 1e18) / rateT3);

        uint256 balance1 = eth.balanceOf(alice);
        uint256 balance2 = btc.balanceOf(alice);
        uint256 aliceBorrow = jusdBank.getBorrowBalance(alice);
        assertEq(balance1, 5);
        assertEq(aliceBorrow, (1_000_001_904 * rateT3) / 1e18);
        assertEq(balance2, 5);
        vm.stopPrank();
    }

    function testWithDrawFailNotMax() public {
        eth.transfer(alice, 10e18);
        btc.transfer(alice, 10e8);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        btc.approve(address(jusdBank), 10e8);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        vm.warp(1000);
        jusdBank.deposit(alice, address(btc), 10e8, alice);
        vm.warp(2000);
        jusdBank.borrow(6000e6, alice, false);
        vm.warp(3000);
        jusdBank.withdraw(address(eth), 10e18, alice, false);
        cheats.expectRevert("AFTER_WITHDRAW_ACCOUNT_IS_NOT_SAFE");
        jusdBank.withdraw(address(btc), 10e8, alice, false);
        vm.stopPrank();
    }

    function testRepayAndWithdrawAll() public {
        btc.transfer(alice, 10e8);
        eth.transfer(alice, 100e18);

        vm.startPrank(address(jusdBank));
        jusd.transfer(alice, 1000e6);
        vm.stopPrank();
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        btc.approve(address(jusdBank), 10e8);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        jusdBank.deposit(alice, address(btc), 10e8, alice);
        vm.warp(1000);
        jusdBank.borrow(5000e6, alice, false);
        uint256 rateT2 = jusdBank.tRate();
        jusd.approve(address(jusdBank), 6000e6);
        vm.warp(2000);
        jusdBank.repay(6000e6, alice);
        jusdBank.withdraw(address(eth), 10e18, alice, false);
        uint256 adjustAmount = jusdBank.getBorrowBalance(alice);
        uint256 rateT3 = jusdBank.tRate();

        emit log_uint(6000e6 - (((5000e6 * 1e18) / rateT2 + 1) * rateT3) / 1e18);
        assertEq(jusd.balanceOf(alice), 999_996_829);
        assertEq(0, adjustAmount);
        assertEq(100e18, eth.balanceOf(alice));
        assertEq(false, jusdBank.getIfHasCollateral(alice, address(eth)));
        vm.stopPrank();
    }

    function testDepositTooManyThenWithdraw() public {
        jusdBank.updateReserveParam(address(eth), 8e17, 2300e18, 230e18, 100_000e18);
        jusdBank.updateMaxBorrowAmount(200_000e18, 300_000e18);
        eth.transfer(alice, 200e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 200e18);
        jusdBank.deposit(alice, address(eth), 200e18, alice);
        jusdBank.borrow(100_000e6, alice, false);
        uint256 withdrawAmount = jusdBank.getMaxWithdrawAmount(address(eth), alice);
        assertEq(withdrawAmount, 75e18);
        jusdBank.withdraw(address(eth), 75e18, alice, false);
        vm.stopPrank();
    }

    function testWithdrawInternal() public {
        eth.transfer(alice, 10e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        jusdBank.withdraw(address(eth), 1e18, bob, true);
        assertEq(IJUSDBank(jusdBank).getDepositBalance(address(eth), bob), 1e18);
    }

    function testWithdrawInternalExceed() public {
        eth.transfer(alice, 10e18);
        eth.transfer(bob, 2030e18);

        vm.startPrank(bob);
        eth.approve(address(jusdBank), 2030e18);
        jusdBank.deposit(bob, address(eth), 2030e18, bob);
        vm.stopPrank();

        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        cheats.expectRevert("EXCEED_THE_MAX_DEPOSIT_AMOUNT_PER_ACCOUNT");
        jusdBank.withdraw(address(eth), 10e18, bob, true);
    }

    function testSelfWithdraw() public {
        eth.transfer(alice, 10e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        for (uint256 i = 0; i < 100; i++) {
            jusdBank.withdraw(address(eth), 10e18, alice, true);
        }

        address[] memory list = jusdBank.getUserCollateralList(alice);
        uint256 maxBorrow = jusdBank.getDepositMaxMintAmount(alice);

        console.log("maxBorrow:", maxBorrow);
        console.log(list.length);
        assertEq(list.length, 1);

        cheats.expectRevert("AFTER_BORROW_ACCOUNT_IS_NOT_SAFE");
        jusdBank.borrow(100_000e6, alice, false);
    }
}
