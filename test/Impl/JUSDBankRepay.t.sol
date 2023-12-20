/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.9;

import "../init/JUSDBankInit.t.sol";

contract JUSDBankRepayTest is JUSDBankInitTest {
    function testRepayJUSDSuccess() public {
        eth.transfer(alice, 100e18);

        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        jusdBank.borrow(5000e6, alice, false);
        jusd.approve(address(jusdBank), 5000e6);
        jusdBank.repay(5000e6, alice);

        uint256 adjustAmount = jusdBank.getBorrowBalance(alice);
        assertEq(adjustAmount, 0);
        assertEq(jusd.balanceOf(alice), 0);
        assertEq(eth.balanceOf(alice), 90e18);
        assertEq(jusdBank.getDepositBalance(address(eth), alice), 10e18);
        vm.stopPrank();
    }

    function testRepayJUSDtRateSuccess() public {
        eth.transfer(alice, 100e18);
        btc.transfer(alice, 100e8);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        btc.approve(address(jusdBank), 10e8);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        vm.warp(1000);
        jusdBank.deposit(alice, address(btc), 10e8, alice);
        vm.warp(2000);
        // max borrow amount
        uint256 rateT2 = jusdBank.getTRate();
        jusdBank.borrow(3000e6, alice, false);
        jusd.approve(address(jusdBank), 6000e6);
        vm.warp(3000);
        uint256 rateT3 = jusdBank.getTRate();
        jusd.approve(address(jusdBank), 3000e6);
        jusdBank.repay(1500e6, alice);
        jusdBank.borrow(1000e6, alice, false);
        uint256 aliceBorrowed = jusdBank.getBorrowBalance(alice);
        emit log_uint(
            (3000e6 * 1e18) /
                rateT2 +
                1 -
                (1500e6 * 1e18) /
                rateT3 +
                (1000e6 * 1e18) /
                rateT3 +
                1
        );
        console.log((2499997149 * rateT3) / 1e18);
        vm.stopPrank();
        assertEq(aliceBorrowed, 2500001903);
    }

    function testRepayTotalJUSDtRateSuccess() public {
        eth.transfer(alice, 100e18);
        vm.startPrank(address(jusdBank));
        jusd.transfer(alice, 1000e6);
        vm.stopPrank();
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(5000e6, alice, false);
        uint256 rateT1 = jusdBank.getTRate();
        uint256 usedBorrowed = (5000e6 * 1e18) / rateT1;
        jusd.approve(address(jusdBank), 6000e6);
        vm.warp(2000);
        jusdBank.repay(6000e6, alice);
        uint256 aliceBorrowed = jusdBank.getBorrowBalance(alice);
        uint256 rateT2 = jusdBank.getTRate();
        emit log_uint(6000e6 - ((usedBorrowed * rateT2) / 1e18 + 1));
        assertEq(jusd.balanceOf(alice), 999996829);
        assertEq(0, aliceBorrowed);
        vm.stopPrank();
    }

    function testRepayAmountisZero() public {
        eth.transfer(alice, 100e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        jusdBank.borrow(5000e6, alice, false);
        cheats.expectRevert("REPAY_AMOUNT_IS_ZERO");
        jusdBank.repay(0, alice);
        vm.stopPrank();
    }

    // eg: emit log_uint((3000e18 * 1e18/ rateT2) * rateT2 / 1e18)
    function testRepayJUSDInSameTimestampSuccess() public {
        eth.transfer(alice, 100e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        vm.warp(2000);
        uint256 rateT2 = jusdBank.getTRate();
        jusdBank.borrow(3000e6, alice, false);
        uint256 aliceUsedBorrowed = jusdBank.getBorrowBalance(alice);
        emit log_uint((3000e6 * 1e18) / rateT2);
        jusd.approve(address(jusdBank), 3000e6);
        jusdBank.repay(3000e6, alice);
        uint256 aliceBorrowed = jusdBank.getBorrowBalance(alice);
        assertEq(aliceUsedBorrowed, 3000e6);
        assertEq(aliceBorrowed, 0);
        vm.stopPrank();
    }

    function testRepayInSameTimestampSuccess() public {
        eth.transfer(alice, 100e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        vm.warp(2000);
        uint256 rateT2 = jusdBank.getTRate();
        jusdBank.borrow(3000e6, alice, false);
        uint256 aliceUsedBorrowed = jusdBank.getBorrowBalance(alice);
        assertEq(aliceUsedBorrowed, 3000e6);
        vm.warp(2001);
        uint256 rateT3 = jusdBank.getTRate();
        jusd.approve(address(jusdBank), 3000e6);
        jusdBank.repay(3000e6, alice);
        uint256 aliceBorrowed = jusdBank.getBorrowBalance(alice);
        emit log_uint((3000e6 * 1e18) / rateT2 + 1 - (3000e6 * 1e18) / rateT3);

        assertEq(aliceBorrowed, (3 * rateT3) / 1e18);
        vm.stopPrank();
    }

    function testRepayByGeneralRepay() public {
        eth.transfer(alice, 10e18);
        usdc.mint(alice, 1000e6);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        jusdBank.borrow(3000e6, alice, false);

        IERC20(usdc).approve(address(generalRepay), 1000e6);
        bytes memory test;
        generalRepay.repayJUSD(address(usdc), 1000e6, alice, test);
        assertEq(jusdBank.getBorrowBalance(alice), 2000e6);
    }

    function testRepayByGeneralRepayTooBig() public {
        eth.transfer(alice, 10e18);
        usdc.mint(alice, 1000e6);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        jusdBank.borrow(500e6, alice, false);

        IERC20(usdc).approve(address(generalRepay), 1000e6);
        bytes memory test;
        generalRepay.repayJUSD(address(usdc), 1000e6, alice, test);
        assertEq(jusdBank.getBorrowBalance(alice), 0);
        assertEq(usdc.balanceOf(alice), 500e6);
    }

    function testRepayCollateralWallet() public {
        eth.transfer(alice, 15e18);
        generalRepay.setWhiteListContract(address(swapContract), true);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        jusdBank.borrow(3000e6, alice, false);

        eth.approve(address(generalRepay), 1e18);

        bytes memory data = swapContract.getSwapToUSDCData(1e18, address(eth));
        bytes memory param = abi.encode(
            swapContract,
            swapContract,
            1000e6,
            data
        );
        generalRepay.repayJUSD(address(eth), 1e18, alice, param);
        assertEq(jusdBank.getBorrowBalance(alice), 2000e6);
        assertEq(eth.balanceOf(alice), 4e18);
    }

    function testRepayCollateralWalletTooBig() public {
        eth.transfer(alice, 15e18);
        generalRepay.setWhiteListContract(address(swapContract), true);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        jusdBank.borrow(1000e6, alice, false);

        eth.approve(address(generalRepay), 2e18);

        bytes memory data = swapContract.getSwapToUSDCData(2e18, address(eth));
        bytes memory param = abi.encode(
            swapContract,
            swapContract,
            2000e6,
            data
        );
        generalRepay.repayJUSD(address(eth), 2e18, alice, param);
        assertEq(jusdBank.getBorrowBalance(alice), 0);
        assertEq(eth.balanceOf(alice), 3e18);
        assertEq(usdc.balanceOf(alice), 1000e6);
    }
}
