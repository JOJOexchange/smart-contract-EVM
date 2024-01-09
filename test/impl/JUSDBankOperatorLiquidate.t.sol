/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../init/JUSDBankInit.t.sol";
import "../../src/FlashLoanLiquidate.sol";
import {
    LiquidateCollateralRepayNotEnough,
    LiquidateCollateralInsuranceNotEnough,
    LiquidateCollateralLiquidatedNotEnough
} from "../mocks/MockWrongLiquidateFlashloan.sol";

// Check jusdbank's liquidation
contract JUSDBankOperatorLiquidateTest is JUSDBankInitTest {
    function testLiquidateRevert() public {
        eth.transfer(alice, 10e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);

        // eth 10 0.8 1000 8000
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();

        vm.warp(2000);
        ethOracle.setMarkPrice(900e6);

        jusd.mint(50_000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50_000e6);
        FlashLoanLiquidate flashLoanLiquidate =
            new FlashLoanLiquidate(address(jusdBank), address(jusdExchange), address(usdc), address(jusd), insurance);
        bytes memory data = swapContract.getSwapToUSDCData(10e18, address(eth));
        bytes memory param = abi.encode(swapContract, address(this), address(bob), 9000e6, data);
        // liquidate
        vm.startPrank(bob);
        bytes memory afterParam = abi.encode(address(flashLoanLiquidate), param);

        cheats.expectRevert("approve target is not in the whitelist");
        jusdBank.liquidate(alice, address(eth), bob, 10e18, afterParam, 900e6);
        vm.stopPrank();
        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        vm.startPrank(bob);
        cheats.expectRevert("swap target is not in the whitelist");
        jusdBank.liquidate(alice, address(eth), bob, 10e18, afterParam, 900e6);

        bytes memory param2 = abi.encode(swapContract, swapContract, address(bob), 19_000e6, data);
        cheats.expectRevert("receive amount is too small");
        bytes memory afterParam2 = abi.encode(address(flashLoanLiquidate), param2);
        jusdBank.liquidate(alice, address(eth), bob, 10e18, afterParam2, 900e6);

        bytes memory data2 = abi.encodeWithSignature("swap");
        bytes memory param3 = abi.encode(swapContract, swapContract, address(bob), 9000e6, data2);
        bytes memory afterParam3 = abi.encode(address(flashLoanLiquidate), param3);
        cheats.expectRevert();
        jusdBank.liquidate(alice, address(eth), bob, 10e18, afterParam3, 900e6);
        vm.stopPrank();
    }

    function testLiquidateAll() public {
        eth.transfer(alice, 10e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);

        // eth 10 0.8 1000 8000
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();

        // price exchange 900 * 10 * 0.825 = 7425
        // liquidateAmount = 7695, USDJBorrow 7426 liquidationPriceOff = 0.05 priceOff = 855 actualJUSD =
        // 8,251.1111111111 insuranceFee = 8,25.11111111111
        // actualCollateral 9.6504223522
        vm.warp(2000);
        ethOracle.setMarkPrice(900e6);

        //init flashloanRepay
        jusd.mint(50_000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50_000e6);
        FlashLoanLiquidate flashLoanLiquidate =
            new FlashLoanLiquidate(address(jusdBank), address(jusdExchange), address(usdc), address(jusd), insurance);

        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        bytes memory data = swapContract.getSwapToUSDCData(10e18, address(eth));
        bytes memory param = abi.encode(swapContract, swapContract, address(bob), 9000e6, data);

        // liquidate

        vm.startPrank(bob);

        uint256 aliceUsedBorrowed = jusdBank.getBorrowBalance(alice);
        bytes memory afterParam = abi.encode(address(flashLoanLiquidate), param);
        Types.LiquidateData memory liq = jusdBank.liquidate(alice, address(eth), bob, 10e18, afterParam, 900e6);

        //judge
        uint256 bobDeposit = jusdBank.getDepositBalance(address(eth), bob);
        uint256 aliceDeposit = jusdBank.getDepositBalance(address(eth), alice);
        uint256 bobBorrow = jusdBank.getBorrowBalance(bob);
        uint256 aliceBorrow = jusdBank.getBorrowBalance(alice);
        uint256 insuranceUSDC = IERC20(usdc).balanceOf(insurance);
        uint256 aliceUSDC = IERC20(usdc).balanceOf(alice);
        uint256 bobUSDC = IERC20(usdc).balanceOf(bob);
        console.log((((aliceUsedBorrowed * 1e18) / 855_000_000) * 1e18) / 9e17);
        console.log((((aliceUsedBorrowed * 1e17) / 1e18) * 1e18) / 9e17);
        console.log(((10e18 - liq.actualCollateral) * 900e6) / 1e18);
        console.log((((liq.actualCollateral * 900e6) / 1e18) * 5e16) / 1e18);

        assertEq(aliceDeposit, 0);
        assertEq(bobDeposit, 0);
        assertEq(bobBorrow, 0);
        assertEq(aliceBorrow, 0);
        assertEq(liq.actualCollateral, 9_650_428_473_034_437_946);
        assertEq(insuranceUSDC, 825_111_634);
        assertEq(aliceUSDC, 314_614_374);
        assertEq(bobUSDC, 434_269_282);

        // logs
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

    // liquidated is subaccount
    function testLiquidatedIsSubaccountAll() public {
        eth.transfer(alice, 10e18);

        vm.startPrank(alice);
        address aliceSub = subaccountFactory.newSubaccount();
        eth.approve(address(jusdBank), 10e18);

        // eth 10 0.8 1000 8000 deposit to aliceSub
        jusdBank.deposit(alice, address(eth), 10e18, aliceSub);
        vm.warp(1000);

        bytes memory dataBorrow = jusdBank.getBorrowData(7426e6, aliceSub, false);
        Subaccount(aliceSub).execute(address(jusdBank), dataBorrow, 0);
        vm.stopPrank();

        // price exchange 900 * 10 * 0.825 = 7425
        // liquidateAmount = 7695, USDJBorrow 7426 liquidationPriceOff = 0.05 priceOff = 855 actualJUSD =
        // 8,251.1111111111 insuranceFee = 8,25.11111111111
        // actualCollateral 9.6504223522
        vm.warp(2000);
        ethOracle.setMarkPrice(900e6);

        //init flashloanRepay
        jusd.mint(50_000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50_000e6);
        FlashLoanLiquidate flashLoanLiquidate =
            new FlashLoanLiquidate(address(jusdBank), address(jusdExchange), address(usdc), address(jusd), insurance);
        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        bytes memory data = swapContract.getSwapToUSDCData(10e18, address(eth));
        bytes memory param = abi.encode(swapContract, swapContract, address(bob), 9000e6, data);

        // liquidate

        vm.startPrank(bob);
        // uint256 aliceSubUsedBorrowed = jusdBank.getBorrowBalance(aliceSub);
        bytes memory afterParam = abi.encode(address(flashLoanLiquidate), param);
        Types.LiquidateData memory liq = jusdBank.liquidate(aliceSub, address(eth), bob, 10e18, afterParam, 900e6);

        //judge
        // uint256 bobBorrow = jusdBank.getBorrowBalance(bob);
        // uint256 aliceSubBorrow = jusdBank.getBorrowBalance(aliceSub);
        uint256 insuranceUSDC = IERC20(usdc).balanceOf(insurance);
        uint256 aliceSubUSDC = IERC20(usdc).balanceOf(aliceSub);
        uint256 bobUSDC = IERC20(usdc).balanceOf(bob);
        // console.log((((aliceSubUsedBorrowed * 1e18) / 855000000) * 1e18) / 9e17);
        // console.log((((aliceSubUsedBorrowed * 1e17) / 1e18) * 1e18) / 9e17);
        // console.log(((10e18 - liq.actualCollateral) * 900e6) / 1e18);
        // console.log((((liq.actualCollateral * 900e6) / 1e18) * 5e16) / 1e18);

        // assertEq(bobBorrow, 0);
        // assertEq(aliceSubBorrow, 0);
        assertEq(liq.actualCollateral, 9_650_428_473_034_437_946);
        assertEq(insuranceUSDC, 825_111_634);
        assertEq(aliceSubUSDC, 314_614_374);
        assertEq(bobUSDC, 434_269_282);

        // logs
        console.log("liquidate amount", liq.actualCollateral);
        // console.log("bob borrow", bobBorrow);
        // console.log("alice borrow", aliceSubBorrow);
        console.log("bob usdc", bobUSDC);
        console.log("alice usdc", aliceSubUSDC);
        console.log("insurance balance", insuranceUSDC);
        vm.stopPrank();

        vm.startPrank(alice);
        bytes memory transferData = abi.encodeWithSignature("transfer(address,uint256)", alice, aliceSubUSDC);
        Subaccount(aliceSub).execute(address(usdc), transferData, 0);
        assertEq(IERC20(usdc).balanceOf(aliceSub), 0);
        assertEq(IERC20(usdc).balanceOf(alice), aliceSubUSDC);
    }

    function testLiquidateWhiteListOpen() public {
        eth.transfer(alice, 10e18);
        bool isOpen = jusdBank.isLiquidatorWhitelistOpen();
        assertEq(isOpen, false);
        jusdBank.liquidatorWhitelistOpen();
        jusdBank.addLiquidator(bob);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);

        // eth 10 0.8 1000 8000
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();

        // price exchange 900 * 10 * 0.825 = 7425
        // liquidateAmount = 7695, USDJBorrow 7426 liquidationPriceOff = 0.05 priceOff = 855 actualJUSD =
        // 8,251.1111111111 insuranceFee = 8,25.11111111111
        // actualCollateral 9.6504223522
        vm.warp(2000);
        ethOracle.setMarkPrice(900e6);

        //init flashloanRepay
        jusd.mint(50_000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50_000e6);
        FlashLoanLiquidate flashLoanLiquidate =
            new FlashLoanLiquidate(address(jusdBank), address(jusdExchange), address(usdc), address(jusd), insurance);

        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        bytes memory data = swapContract.getSwapToUSDCData(10e18, address(eth));
        bytes memory param = abi.encode(swapContract, swapContract, address(bob), 9000e6, data);

        // liquidate

        vm.startPrank(bob);

        uint256 aliceUsedBorrowed = jusdBank.getBorrowBalance(alice);
        bytes memory afterParam = abi.encode(address(flashLoanLiquidate), param);
        Types.LiquidateData memory liq = jusdBank.liquidate(alice, address(eth), bob, 10e18, afterParam, 900e6);

        //judge
        uint256 bobDeposit = jusdBank.getDepositBalance(address(eth), bob);
        uint256 aliceDeposit = jusdBank.getDepositBalance(address(eth), alice);
        uint256 bobBorrow = jusdBank.getBorrowBalance(bob);
        uint256 aliceBorrow = jusdBank.getBorrowBalance(alice);
        uint256 insuranceUSDC = IERC20(usdc).balanceOf(insurance);
        uint256 aliceUSDC = IERC20(usdc).balanceOf(alice);
        uint256 bobUSDC = IERC20(usdc).balanceOf(bob);
        console.log((((aliceUsedBorrowed * 1e18) / 855_000_000) * 1e18) / 9e17);
        console.log((((aliceUsedBorrowed * 1e17) / 1e18) * 1e18) / 9e17);
        console.log(((10e18 - liq.actualCollateral) * 900e6) / 1e18);
        console.log((((liq.actualCollateral * 900e6) / 1e18) * 5e16) / 1e18);

        assertEq(aliceDeposit, 0);
        assertEq(bobDeposit, 0);
        assertEq(bobBorrow, 0);
        assertEq(aliceBorrow, 0);
        assertEq(liq.actualCollateral, 9_650_428_473_034_437_946);
        assertEq(insuranceUSDC, 825_111_634);
        assertEq(aliceUSDC, 314_614_374);
        assertEq(bobUSDC, 434_269_282);

        // logs
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

    function testLiquidatePart() public {
        eth.transfer(alice, 10e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);

        // eth 10 0.8 1000 8000
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();

        // price exchange 900 * 10 * 0.825 = 7425
        // liquidateAmount = 7695, USDJBorrow 7426 liquidationPriceOff = 0.05 priceOff = 855 actualJUSD =
        // 8,251.1111111111 insuranceFee = 8,25.11111111111
        // actualCollateral 9.6504223522
        vm.warp(2000);
        ethOracle.setMarkPrice(900e6);

        //init flashloanRepay
        jusd.mint(50_000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50_000e6);
        FlashLoanLiquidate flashLoanLiquidate =
            new FlashLoanLiquidate(address(jusdBank), address(jusdExchange), address(usdc), address(jusd), insurance);
        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        // flashLoanLiquidate.setOracle(address(eth), address(jojoOracle900));

        bytes memory data = swapContract.getSwapToUSDCData(5e18, address(eth));
        bytes memory param = abi.encode(swapContract, swapContract, address(bob), 4500e6, data);

        // liquidate

        vm.startPrank(bob);

        uint256 aliceUsedBorrowed = jusdBank.getBorrowBalance(alice);
        bytes memory afterParam = abi.encode(address(flashLoanLiquidate), param);
        Types.LiquidateData memory liq = jusdBank.liquidate(alice, address(eth), bob, 5e18, afterParam, 900e6);

        assertEq(jusdBank.isAccountSafe(alice), true);

        //judge
        uint256 bobDeposit = jusdBank.getDepositBalance(address(eth), bob);
        uint256 aliceDeposit = jusdBank.getDepositBalance(address(eth), alice);
        uint256 bobBorrow = jusdBank.getBorrowBalance(bob);
        uint256 aliceBorrow = jusdBank.getBorrowBalance(alice);
        uint256 insuranceUSDC = IERC20(usdc).balanceOf(insurance);
        uint256 aliceUSDC = IERC20(usdc).balanceOf(alice);
        uint256 bobUSDC = IERC20(usdc).balanceOf(bob);
        console.log((((5e18 * 855_000_000) / 1e18) * 9e17) / 1e18);
        // console.log((aliceUsedBorrowed * 1e17 / 1e18)* 1e18 / 9e17);
        console.log((((liq.actualCollateral * 900e6) / 1e18) * 5e16) / 1e18);

        assertEq(aliceDeposit, 5e18);
        assertEq(bobDeposit, 0);
        assertEq(bobBorrow, 0);
        assertEq(aliceBorrow, aliceUsedBorrowed - 3_847_500_000);
        assertEq(liq.actualCollateral, 5e18);
        assertEq(insuranceUSDC, 427_500_000);
        assertEq(aliceUSDC, 0);
        assertEq(bobUSDC, 225_000_000);

        // logs
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

    /// @notice user borrow jusd account is not safe
    function testHandleDebt() public {
        eth.transfer(alice, 10e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);

        // eth 10 0.8 1000 8000
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();

        // price exchange 900 * 10 * 0.825 = 7425
        // liquidateAmount = 7695, USDJBorrow 7426 liquidationPriceOff = 0.05 priceOff = 855 actualJUSD =
        // 8,251.1111111111 insuranceFee = 8,25.11111111111
        // actualCollateral 9.6504223522
        vm.warp(2000);
        ethOracle.setMarkPrice(500e6);

        //init flashloanRepay
        jusd.mint(50_000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50_000e6);
        FlashLoanLiquidate flashLoanLiquidate =
            new FlashLoanLiquidate(address(jusdBank), address(jusdExchange), address(usdc), address(jusd), insurance);

        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        bytes memory data = swapContract.getSwapToUSDCData(10e18, address(eth));
        bytes memory param = abi.encode(swapContract, swapContract, address(bob), 5000e6, data);

        // liquidate

        vm.startPrank(bob);

        uint256 aliceUsedBorrowed = jusdBank.getBorrowBalance(alice);
        bytes memory afterParam = abi.encode(address(flashLoanLiquidate), param);
        Types.LiquidateData memory liq = jusdBank.liquidate(alice, address(eth), bob, 10e18, afterParam, 900e6);

        //judge
        uint256 bobDeposit = jusdBank.getDepositBalance(address(eth), bob);
        uint256 aliceDeposit = jusdBank.getDepositBalance(address(eth), alice);
        uint256 bobBorrow = jusdBank.getBorrowBalance(bob);
        uint256 aliceBorrow = jusdBank.getBorrowBalance(alice);
        uint256 insuranceUSDC = IERC20(usdc).balanceOf(insurance);
        uint256 aliceUSDC = IERC20(usdc).balanceOf(alice);
        uint256 bobUSDC = IERC20(usdc).balanceOf(bob);
        uint256 insuranceBorrow = jusdBank.getBorrowBalance(insurance);

        assertEq(aliceDeposit, 0);
        assertEq(bobDeposit, 0);
        assertEq(bobBorrow, 0);
        assertEq(aliceBorrow, aliceUsedBorrowed - 4275e6);
        assertEq(liq.actualCollateral, 10e18);
        assertEq(insuranceUSDC, 475_000_000);
        assertEq(aliceUSDC, 0);
        assertEq(bobUSDC, 250_000_000);
        assertEq(insuranceBorrow, 0);

        // logs
        console.log("liquidate amount", liq.actualCollateral);
        console.log("bob deposit", bobDeposit);
        console.log("alice deposit", aliceDeposit);
        console.log("bob borrow", bobBorrow);
        console.log("alice borrow", aliceBorrow);
        console.log("bob usdc", bobUSDC);
        console.log("alice usdc", aliceUSDC);
        console.log("insurance balance", insuranceUSDC);
        console.log("insurance borrow", insuranceBorrow);
        vm.stopPrank();
        address[] memory liquidaters = new address[](1);
        liquidaters[0] = alice;
        jusdBank.handleDebt(liquidaters);
    }

    function testRepayAmountNotEnough() public {
        eth.transfer(alice, 10e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);

        jusdBank.deposit(alice, address(eth), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();

        vm.warp(2000);
        ethOracle.setMarkPrice(900e6);

        //init flashloanRepay
        jusd.mint(50_000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50_000e6);
        LiquidateCollateralRepayNotEnough flashLoanLiquidate = new LiquidateCollateralRepayNotEnough(
            address(jusdBank), address(jusdExchange), address(usdc), address(jusd), insurance
        );

        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        bytes memory data = swapContract.getSwapToUSDCData(10e18, address(eth));
        bytes memory param = abi.encode(swapContract, swapContract, address(bob), data);

        // liquidate
        vm.startPrank(bob);
        bytes memory afterParam = abi.encode(address(flashLoanLiquidate), param);
        cheats.expectRevert("REPAY_AMOUNT_NOT_ENOUGH");
        jusdBank.liquidate(alice, address(eth), bob, 10e18, afterParam, 900e6);
    }

    function testInsuranceAmountNotEnough() public {
        eth.transfer(alice, 10e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);

        // eth 10 0.8 1000 8000
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();

        vm.warp(2000);
        ethOracle.setMarkPrice(900e6);

        //init flashloanRepay
        jusd.mint(50_000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50_000e6);
        LiquidateCollateralInsuranceNotEnough flashLoanLiquidate = new LiquidateCollateralInsuranceNotEnough(
            address(jusdBank), address(jusdExchange), address(usdc), address(jusd), insurance
        );

        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        bytes memory data = swapContract.getSwapToUSDCData(10e18, address(eth));
        bytes memory param = abi.encode(swapContract, swapContract, address(bob), data);

        // liquidate
        vm.startPrank(bob);
        bytes memory afterParam = abi.encode(address(flashLoanLiquidate), param);
        cheats.expectRevert("INSURANCE_AMOUNT_NOT_ENOUGH");
        jusdBank.liquidate(alice, address(eth), bob, 10e18, afterParam, 900e6);
    }

    function testLiquidatedAmountNotEnough() public {
        eth.transfer(alice, 10e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);

        // eth 10 0.8 1000 8000
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();

        vm.warp(2000);
        ethOracle.setMarkPrice(900e6);

        //init flashloanRepay
        jusd.mint(50_000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50_000e6);
        LiquidateCollateralLiquidatedNotEnough flashLoanLiquidate = new LiquidateCollateralLiquidatedNotEnough(
            address(jusdBank), address(jusdExchange), address(usdc), address(jusd), insurance
        );

        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        bytes memory data = swapContract.getSwapToUSDCData(10e18, address(eth));
        bytes memory param = abi.encode(swapContract, swapContract, address(bob), data);

        // liquidate
        vm.startPrank(bob);
        bytes memory afterParam = abi.encode(address(flashLoanLiquidate), param);
        cheats.expectRevert("LIQUIDATED_AMOUNT_NOT_ENOUGH");
        jusdBank.liquidate(alice, address(eth), bob, 10e18, afterParam, 900e6);
    }

    function testLiquidateOperatorNotInWhiteList() public {
        // liquidator is in the whiteliste but operator is not
        eth.transfer(alice, 10e18);
        bool isOpen = jusdBank.isLiquidatorWhitelistOpen();
        assertEq(isOpen, false);
        jusdBank.liquidatorWhitelistOpen();
        jusdBank.addLiquidator(bob);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);

        // eth 10 0.8 1000 8000
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();

        // price exchange 900 * 10 * 0.825 = 7425
        // liquidateAmount = 7695, USDJBorrow 7426 liquidationPriceOff = 0.05 priceOff = 855 actualJUSD =
        // 8,251.1111111111 insuranceFee = 8,25.11111111111
        // actualCollateral 9.6504223522
        vm.warp(2000);
        ethOracle.setMarkPrice(900e6);

        //init flashloanRepay
        jusd.mint(50_000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50_000e6);
        FlashLoanLiquidate flashLoanLiquidate =
            new FlashLoanLiquidate(address(jusdBank), address(jusdExchange), address(usdc), address(jusd), insurance);

        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        bytes memory data = swapContract.getSwapToUSDCData(10e18, address(eth));
        bytes memory param = abi.encode(swapContract, swapContract, address(bob), 9000e6, data);

        // liquidate

        vm.startPrank(bob);
        jusdBank.setOperator(jim, true);
        vm.stopPrank();
        vm.startPrank(jim);
        bytes memory afterParam = abi.encode(address(flashLoanLiquidate), param);
        Types.LiquidateData memory liqBefore = jusdBank.liquidate(alice, address(eth), bob, 10e18, afterParam, 900e6);

        //judge
        uint256 bobDeposit = jusdBank.getDepositBalance(address(eth), bob);
        uint256 aliceDeposit = jusdBank.getDepositBalance(address(eth), alice);
        uint256 bobBorrow = jusdBank.getBorrowBalance(bob);
        uint256 aliceBorrow = jusdBank.getBorrowBalance(alice);
        uint256 insuranceUSDC = IERC20(usdc).balanceOf(insurance);
        uint256 aliceUSDC = IERC20(usdc).balanceOf(alice);
        uint256 bobUSDC = IERC20(usdc).balanceOf(bob);

        assertEq(aliceDeposit, 0);
        assertEq(bobDeposit, 0);
        assertEq(bobBorrow, 0);
        assertEq(aliceBorrow, 0);
        assertEq(liqBefore.actualCollateral, 9_650_428_473_034_437_946);
        assertEq(insuranceUSDC, 825_111_634);
        assertEq(aliceUSDC, 314_614_374);
        assertEq(bobUSDC, 434_269_282);
        vm.stopPrank();

        jusdBank.removeLiquidator(bob);
        jusdBank.addLiquidator(jim);
        vm.startPrank(jim);
        cheats.expectRevert("LIQUIDATOR_NOT_IN_THE_WHITELIST");
        jusdBank.liquidate(alice, address(eth), bob, 10e18, afterParam, 900e6);
    }

    function testLiquidateNotOperator() public {
        // liquidator is in the whiteliste but operator is not
        eth.transfer(alice, 10e18);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);

        // eth 10 0.8 1000 8000
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        vm.warp(1000);
        jusdBank.borrow(7426e6, alice, false);
        vm.stopPrank();

        //init flashloanRepay
        jusd.mint(50_000e6);
        IERC20(jusd).transfer(address(jusdExchange), 50_000e6);
        FlashLoanLiquidate flashLoanLiquidate =
            new FlashLoanLiquidate(address(jusdBank), address(jusdExchange), address(usdc), address(jusd), insurance);

        flashLoanLiquidate.setWhiteListContract(address(swapContract), true);
        bytes memory data = swapContract.getSwapToUSDCData(10e18, address(eth));
        bytes memory param = abi.encode(swapContract, swapContract, address(bob), data);

        // liquidate
        vm.startPrank(jim);
        bytes memory afterParam = abi.encode(address(flashLoanLiquidate), param);
        cheats.expectRevert("CAN_NOT_OPERATE_ACCOUNT");
        jusdBank.liquidate(alice, address(eth), bob, 10e18, afterParam, 900e6);
        vm.stopPrank();
    }
}
