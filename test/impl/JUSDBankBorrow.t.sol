/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../init/JUSDBankInit.t.sol";

// Check jusdbank's borrow
contract JUSDBankBorrowTest is JUSDBankInitTest {
    // no tRate just one token
    function testBorrowJUSDSuccess() public {
        eth.transfer(alice, 100e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        jusdBank.borrow(5000e6, alice, false);
        uint256 jusdBalance = jusdBank.getBorrowBalance(alice);
        assertEq(jusdBalance, 5000e6);
        assertEq(jusd.balanceOf(alice), 5000e6);
        assertEq(eth.balanceOf(alice), 90e18);
        assertEq(jusdBank.getDepositBalance(address(eth), alice), 10e18);
        vm.stopPrank();
    }

    // no tRate two token
    function testBorrow2CollateralJUSDSuccess() public {
        eth.transfer(alice, 100e18);
        btc.transfer(alice, 100e8);

        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        btc.approve(address(jusdBank), 10e8);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        jusdBank.deposit(alice, address(btc), 10e8, alice);
        jusdBank.borrow(6000e6, alice, false);
        uint256 jusdBalance = jusdBank.getBorrowBalance(alice);

        assertEq(jusdBalance, 6000e6);
        assertEq(jusd.balanceOf(alice), 6000e6);
        assertEq(eth.balanceOf(alice), 90e18);
        assertEq(jusdBank.getDepositBalance(address(eth), alice), 10e18);
        assertEq(jusdBank.getDepositBalance(address(btc), alice), 10e8);
        vm.stopPrank();
    }

    // have tRate, one token
    function testBorrowJUSDtRateSuccess() public {
        eth.transfer(alice, 100e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);

        vm.warp(1000);
        jusdBank.borrow(5000e6, alice, false);
        uint256 jusdBalance = jusdBank.getBorrowBalance(alice);
        assertEq(jusdBalance, 5000e6);
        assertEq(jusd.balanceOf(alice), 5000e6);
        assertEq(eth.balanceOf(alice), 90e18);
        assertEq(jusdBank.getDepositBalance(address(eth), alice), 10e18);

        vm.stopPrank();
    }

    //  > max mint amount
    function testBorrowJUSDFailMaxMintAmount() public {
        eth.transfer(alice, 100e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);

        cheats.expectRevert("AFTER_BORROW_ACCOUNT_IS_NOT_SAFE");
        jusdBank.borrow(8001e6, alice, false);
        vm.stopPrank();
    }

    function testBorrowJUSDFailPerAccount() public {
        eth.transfer(alice, 100e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        cheats.expectRevert("EXCEED_THE_MAX_BORROW_AMOUNT_PER_ACCOUNT");
        jusdBank.borrow(100_001e6, alice, false);
        vm.stopPrank();
    }

    function testBorrowJUSDFailTotalAmount() public {
        eth.transfer(alice, 200e18);
        eth.transfer(bob, 200e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 200e18);
        jusdBank.deposit(alice, address(eth), 200e18, alice);
        jusdBank.borrow(100_000e6, alice, false);
        vm.stopPrank();

        vm.startPrank(bob);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(bob, address(eth), 10e18, bob);
        cheats.expectRevert("EXCEED_THE_MAX_BORROW_AMOUNT_TOTAL");
        jusdBank.borrow(5000e6, bob, false);

        vm.stopPrank();
    }

    function testBorrowDepositToJOJO() public {
        eth.transfer(alice, 100e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        jusdBank.borrow(5000e6, alice, true);
        vm.stopPrank();
    }

    // https://github.com/foundry-rs/foundry/issues/3497 for revert test

    function testDepositTooMany() public {
        jusdBank.updateReserveParam(address(eth), 8e17, 2300e18, 230e18, 100_000e6);
        jusdBank.updateMaxBorrowAmount(200_000e6, 300_000e18);
        eth.transfer(alice, 200e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 200e18);
        jusdBank.deposit(alice, address(eth), 200e18, alice);
        cheats.expectRevert("AFTER_BORROW_ACCOUNT_IS_NOT_SAFE");
        jusdBank.borrow(200_000e6, alice, false);
        jusdBank.borrow(100_000e6, alice, false);
        jusdBank.withdraw(address(eth), 75_000_000_000_000_000_000, alice, false);
        vm.stopPrank();
    }

    function testGetDepositMaxData() public {
        jusdBank.updateReserveParam(address(eth), 8e17, 2300e18, 230e18, 100_000e18);
        jusdBank.updateReserveParam(address(btc), 75e16, 2300e18, 230e18, 100_000e18);
        jusdBank.updateMaxBorrowAmount(200_000e18, 300_000e18);
        eth.transfer(alice, 10e18);
        btc.transfer(alice, 1e8);

        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        btc.approve(address(jusdBank), 1e8);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        jusdBank.deposit(alice, address(btc), 1e8, alice);
        jusdBank.borrow(8000e6, alice, false);

        uint256 maxMint = jusdBank.getDepositMaxMintAmount(alice);
        console.log("max mint", maxMint);
    }

    function testDepositTooManyETH() public {
        jusdBank.updateReserveParam(address(eth), 8e17, 2300e18, 230e18, 100_000e6);
        jusdBank.updateReserveParam(address(btc), 75e16, 2300e8, 230e8, 100_000e6);
        jusdBank.updateRiskParam(address(eth), 825e15, 5e16, 1e17);
        jusdBank.updateMaxBorrowAmount(200_000e6, 300_000e6);
        eth.transfer(alice, 200e18);
        btc.transfer(alice, 5e8);

        vm.startPrank(alice);
        eth.approve(address(jusdBank), 200e18);
        btc.approve(address(jusdBank), 10e8);
        jusdBank.deposit(alice, address(eth), 200e18, alice);
        jusdBank.deposit(alice, address(btc), 5e8, alice);
        jusdBank.borrow(100_000e6, alice, false);
        jusdBank.borrow(75_000e6, alice, false);

        uint256 maxWithdraweth = jusdBank.getMaxWithdrawAmount(address(eth), alice);
        console.log("max withdraw eth before fall", maxWithdraweth);
        uint256 maxWithdrawbtc = jusdBank.getMaxWithdrawAmount(address(btc), alice);
        console.log("max withdraw btc before fall", maxWithdrawbtc);

        cheats.expectRevert("AFTER_BORROW_ACCOUNT_IS_NOT_SAFE");
        jusdBank.borrow(1e6, alice, false);
        assertEq(maxWithdraweth, 75_000_000_000_000_000_000);
        assertEq(maxWithdrawbtc, 400_000_000);

        vm.stopPrank();
        btcOracle.setMarkPrice(15_000e16);

        maxWithdraweth = jusdBank.getMaxWithdrawAmount(address(eth), alice);
        console.log("max withdraw eth", maxWithdraweth);
        maxWithdrawbtc = jusdBank.getMaxWithdrawAmount(address(btc), alice);
        console.log("max withdraw btc", maxWithdrawbtc);

        vm.startPrank(alice);

        cheats.expectRevert("AFTER_WITHDRAW_ACCOUNT_IS_NOT_SAFE");
        jusdBank.withdraw(address(eth), 75_000_000_000_000_000_000, alice, false);
        bool ifSafe = jusdBank.isAccountSafe(alice);
        uint256 borrowJUSD = jusdBank.getBorrowBalance(alice);
        uint256 depositAmount = jusdBank.getDepositMaxMintAmount(alice);

        console.log("borrow amount", borrowJUSD);
        console.log("depositAmount amount", depositAmount);
        console.log("alice safe?", ifSafe);
    }
}
