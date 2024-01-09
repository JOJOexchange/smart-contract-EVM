/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../init/JUSDBankInit.t.sol";

// Check jusdbank's deposit
contract JUSDBankTest is JUSDBankInitTest {
    function testDepositSuccess() public {
        eth.transfer(alice, 10e18);
        btc.transfer(alice, 10e8);
        // change msg.sender
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 5e18);
        jusdBank.deposit(alice, address(eth), 5e18, alice);
        uint256 balance = jusdBank.getDepositBalance(address(eth), alice);
        assertEq(balance, 5e18);
        assertEq(jusdBank.getBorrowBalance(msg.sender), 0);
        address[] memory userList = jusdBank.getUserCollateralList(alice);
        assertEq(userList[0], address(eth));
        vm.stopPrank();
    }

    function testAll() public {
        eth.transfer(alice, 10e18);
        // change msg.sender
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 5e18, alice);
        jusdBank.deposit(alice, address(eth), 5e18, alice);
        jusdBank.borrow(1000e6, alice, false);
        jusdBank.borrow(1000e6, alice, false);
        jusd.approve(address(jusdBank), 2000e18);
        jusdBank.repay(1000e6, alice);
        jusdBank.repay(1000e6, alice);
        jusdBank.withdraw(address(eth), 5e18, alice, false);
        jusdBank.withdraw(address(eth), 5e18, alice, false);
        vm.stopPrank();
    }

    function testDepositToBobSuccess() public {
        eth.transfer(alice, 10e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 5);
        jusdBank.deposit(alice, address(eth), 5, bob);
        uint256 balance = jusdBank.getDepositBalance(address(eth), alice);

        assertEq(balance, 0);
        assertEq(jusdBank.getDepositBalance(address(eth), bob), 5);
        vm.stopPrank();
    }

    function testDepositAmountIs0Fail() public {
        eth.transfer(alice, 10e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 5);
        cheats.expectRevert("DEPOSIT_AMOUNT_IS_ZERO");
        jusdBank.deposit(alice, address(eth), 0, alice);
        vm.stopPrank();
    }

    function testDepositFailAmountMoreThanPerAccount() public {
        eth.transfer(alice, 2031e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 2031e18);
        cheats.expectRevert("EXCEED_THE_MAX_DEPOSIT_AMOUNT_PER_ACCOUNT");
        jusdBank.deposit(alice, address(eth), 2031e18, alice);
        vm.stopPrank();
    }

    function testDepositFailAmountMoreTotal() public {
        eth.transfer(alice, 2030e18);
        eth.transfer(bob, 2030e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 2030e18);
        jusdBank.deposit(alice, address(eth), 2030e18, alice);
        vm.stopPrank();
        assertEq(jusdBank.getDepositBalance(address(eth), alice), 2030e18);

        vm.startPrank(bob);
        eth.approve(address(jusdBank), 2030e18);
        cheats.expectRevert("EXCEED_THE_MAX_DEPOSIT_AMOUNT_TOTAL");
        jusdBank.deposit(bob, address(eth), 2030e18, bob);
        vm.stopPrank();
    }

    function testDepositTokenNotInReserve() public {
        TestERC20 mk = new TestERC20("mk", "mk", 18);
        mk.mint(alice, 10e18);
        vm.startPrank(alice);
        mk.approve(address(jusdBank), 10e18);
        cheats.expectRevert("RESERVE_NOT_ALLOW_DEPOSIT");
        jusdBank.deposit(alice, address(mk), 10e18, alice);
        vm.stopPrank();
    }
}
