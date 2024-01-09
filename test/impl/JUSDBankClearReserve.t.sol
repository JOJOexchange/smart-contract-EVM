/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../init/JUSDBankInit.t.sol";
import "../../src/FlashLoanLiquidate.sol";

// Check jusdbank's list/delist
contract JUSDBankClearReserveTest is JUSDBankInitTest {
    /// @notice user borrow jusd account is not safe
    function testClearReserve() public {
        eth.transfer(alice, 10e18);
        btc.transfer(bob, 10e8);

        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        vm.warp(1000);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        vm.warp(2000);
        jusdBank.borrow(3000e6, alice, false);
        vm.stopPrank();
        //eth relist
        jusdBank.delistReserve(address(eth));

        FlashLoanLiquidate flashLoanLiquidate =
            new FlashLoanLiquidate(address(jusdBank), address(jusdExchange), address(usdc), address(jusd), insurance);
        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        //bob liquidate alice
        vm.startPrank(bob);
        bytes memory data = swapContract.getSwapToUSDCData(10e18, address(eth));
        bytes memory param = abi.encode(swapContract, swapContract, address(bob), 10_000e6, data);
        bytes memory afterParam = abi.encode(address(flashLoanLiquidate), param);

        Types.LiquidateData memory liq = jusdBank.liquidate(alice, address(eth), bob, 10e18, afterParam, 1000e6);

        // logs

        uint256 bobDeposit = jusdBank.getDepositBalance(address(eth), bob);
        uint256 aliceDeposit = jusdBank.getDepositBalance(address(eth), alice);
        uint256 bobBorrow = jusdBank.getBorrowBalance(bob);
        uint256 aliceBorrow = jusdBank.getBorrowBalance(alice);
        uint256 insuranceUSDC = IERC20(usdc).balanceOf(insurance);
        uint256 aliceUSDC = IERC20(usdc).balanceOf(alice);
        uint256 bobUSDC = IERC20(usdc).balanceOf(bob);
        console.log("liquidate amount", liq.actualCollateral);
        console.log("bob deposit", bobDeposit);
        console.log("alice deposit", aliceDeposit);
        console.log("bob borrow", bobBorrow);
        console.log("alice borrow", aliceBorrow);
        console.log("bob usdc", bobUSDC);
        console.log("alice usdc", aliceUSDC);
        console.log("insurance balance", insuranceUSDC);
        vm.stopPrank();
    }

    function testClearMock2() public {
        eth.transfer(alice, 10e18);
        btc.transfer(alice, 1e8);

        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        jusdBank.borrow(3000e6, alice, false);
        vm.stopPrank();

        jusdBank.delistReserve(address(eth));

        vm.startPrank(alice);
        btc.approve(address(jusdBank), 1e8);
        jusdBank.deposit(alice, address(btc), 1e8, alice);

        cheats.expectRevert("AFTER_WITHDRAW_ACCOUNT_IS_NOT_SAFE");
        jusdBank.withdraw(address(btc), 1e8, alice, false);
        uint256 maxWithdrawBTC = jusdBank.getMaxWithdrawAmount(address(btc), alice);
        uint256 maxMint = jusdBank.getDepositMaxMintAmount(alice);
        assertEq(maxMint, 14_000e6);
        assertEq(maxWithdrawBTC, 78_571_428);
        vm.stopPrank();
    }

    /// relist and then list
    function testClearAndRegister() public {
        eth.transfer(alice, 10e18);

        vm.startPrank(address(jusdBank));
        jusd.transfer(alice, 1000e6);
        vm.stopPrank();

        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        vm.warp(1000);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        vm.warp(2000);
        jusdBank.borrow(3000e6, alice, false);
        vm.stopPrank();
        vm.warp(3000);
        jusdBank.delistReserve(address(eth));

        vm.warp(4000);
        jusdBank.relistReserve(address(eth));

        vm.startPrank(alice);
        jusdBank.withdraw(address(eth), 1e18, alice, false);
        vm.stopPrank();
        assertEq(jusdBank.getDepositBalance(address(eth), alice), 9e18);
    }
}
