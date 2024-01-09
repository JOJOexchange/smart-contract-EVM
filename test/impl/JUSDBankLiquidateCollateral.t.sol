/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../init/JUSDBankInit.t.sol";
import "../../src/FlashLoanLiquidate.sol";

// Check jusdbank's liquidation
contract JUSDBankLiquidateCollateralTest is JUSDBankInitTest {
    /// @notice user just deposit not borrow, account is safe
    function testLiquidateCollateralAccountIsSafe() public {
        eth.transfer(alice, 10e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        bool ifSafe = jusdBank.isAccountSafe(alice);
        assertEq(ifSafe, true);
        vm.stopPrank();
        vm.startPrank(bob);
        cheats.expectRevert("JOJO_ACCOUNT_IS_SAFE");
        bytes memory afterParam = abi.encode(address(jusd), 10e18);
        jusdBank.liquidate(alice, address(eth), bob, 10e18, afterParam, 0);
        vm.stopPrank();
    }

    function testLiquidateCollateralAmountIsZero() public {
        eth.transfer(alice, 10e18);
        vm.startPrank(address(jusdBank));
        jusd.transfer(bob, 5000e6);
        vm.stopPrank();
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        jusdBank.borrow(5000e6, alice, false);
        vm.stopPrank();
        vm.startPrank(address(this));

        ethOracle.setMarkPrice(550e6);
        vm.stopPrank();
        vm.startPrank(bob);
        jusd.approve(address(jusdBank), 5225e6);
        vm.warp(3000);
        cheats.expectRevert("LIQUIDATE_AMOUNT_IS_ZERO");
        bytes memory afterParam = abi.encode(address(jusd), 5000e6);
        jusdBank.liquidate(alice, address(eth), bob, 0, afterParam, 0);
    }

    function testLiquidateCollateralPriceProtect() public {
        eth.transfer(alice, 10e18);
        vm.startPrank(address(jusdBank));
        jusd.transfer(bob, 5000e6);
        vm.stopPrank();
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();
        ethOracle.setMarkPrice(900e6);
        jusd.mint(50_000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50_000e6);
        FlashLoanLiquidate flashLoanLiquidate =
            new FlashLoanLiquidate(address(jusdBank), address(jusdExchange), address(usdc), address(jusd), insurance);

        bytes memory data = swapContract.getSwapToUSDCData(10e18, address(eth));
        bytes memory param = abi.encode(swapContract, swapContract, address(bob), data);

        vm.startPrank(bob);
        bytes memory afterParam = abi.encode(address(flashLoanLiquidate), param);
        cheats.expectRevert("LIQUIDATION_PRICE_PROTECTION");
        // price 854.9999999885
        jusdBank.liquidate(alice, address(eth), bob, 10e18, afterParam, 854e6);
    }

    function testSelfLiquidateCollateral() public {
        eth.transfer(alice, 10e18);
        vm.startPrank(address(jusdBank));
        jusd.transfer(bob, 5000e6);
        vm.stopPrank();
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();
        vm.startPrank(address(this));
        ethOracle.setMarkPrice(900e6);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.warp(3000);

        bytes memory data = swapContract.getSwapToUSDCData(1e18, address(eth));
        bytes memory param = abi.encode(swapContract, swapContract, address(bob), data);
        FlashLoanLiquidate flashloanRepay =
            new FlashLoanLiquidate(address(jusdBank), address(jusdExchange), address(usdc), address(jusd), insurance);
        bytes memory afterParam = abi.encode(address(flashloanRepay), param);
        cheats.expectRevert("JOJO_SELF_LIQUIDATION_NOT_ALLOWED");
        jusdBank.liquidate(alice, address(eth), alice, 10e18, afterParam, 10e18);
    }

    function testLiquidatorIsNotInWhiteList() public {
        eth.transfer(alice, 10e18);
        bool isOpen = jusdBank.isLiquidatorWhitelistOpen();
        jusdBank.liquidatorWhitelistClose();
        assertEq(isOpen, false);
        jusdBank.liquidatorWhitelistOpen();
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.warp(3000);
        bytes memory data = swapContract.getSwapToUSDCData(1e18, address(eth));
        bytes memory param = abi.encode(swapContract, swapContract, address(bob), data);
        FlashLoanLiquidate flashloanRepay =
            new FlashLoanLiquidate(address(jusdBank), address(jusdExchange), address(usdc), address(jusd), insurance);
        bytes memory afterParam = abi.encode(address(flashloanRepay), param);
        cheats.expectRevert("LIQUIDATOR_NOT_IN_THE_WHITELIST");
        jusdBank.liquidate(alice, address(eth), bob, 1e18, afterParam, 0);
    }
}
