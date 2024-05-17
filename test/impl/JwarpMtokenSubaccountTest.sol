/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "../init/JUSDBankInit.t.sol";
import "../mocks/MockController.sol";
import "../mocks/MockMUSDC.sol";
import "../../src/token/JwrapMUSDCFactory.sol";
import "../../src/FlashLoanLiquidateJwrapMUSDC.sol";

contract JwrapMtokenSubaccountTest is JUSDBankInitTest {
    MockMUSDC public mUsdc;
    TestERC20 public well;
    EmergencyOracle public jwrapMusdcOracle;
    JwrapMUSDCFactory public jwrapMusdc;
    MockController public mockController;
    FlashLoanLiquidateJwrapMUSDC public flashLiquidateJwrapMUSDC;

    function setUpMtokenInfo() public {
        mUsdc = new MockMUSDC("mUsdc", "mUsdc", 8, address(usdc));
        usdc.mint(address(mUsdc), 10_000e6);
        well = new TestERC20("well", "well", 18);
        mockController = new MockController(address(well), address(usdc));
        well.mint(address(mockController), 10e18);
        usdc.mint(address(mockController), 10e6);
        jwrapMusdc = new JwrapMUSDCFactory(
            address(mUsdc),
            address(mockController),
            address(well),
            address(usdc),
            address(jusdBank),
            "JwrapMusdc",
            "JwrapMusdc"
        );
        flashLiquidateJwrapMUSDC = new FlashLoanLiquidateJwrapMUSDC(
            address(jusdBank), address(jusdExchange), address(usdc), address(jusd), insurance, address(jwrapMusdc)
        );
        jwrapMusdcOracle = new EmergencyOracle("JwrapMusdc oracle");
        jwrapMusdcOracle.setMarkPrice(2e14);
        jusdBank.initReserve(
            // token
            address(jwrapMusdc),
            // initialMortgageRate
            9e17,
            // maxDepositAmount
            20_000_000e8,
            // maxDepositAmountPerAccount
            4_000_000e8,
            // maxBorrowValue
            100_000e6,
            // liquidateMortgageRate
            95e16,
            // liquidationPriceOff
            2e16,
            // insuranceFeeRate
            3e16,
            address(jwrapMusdcOracle)
        );
    }

    function testDepositJwrapToken() public {
        setUpMtokenInfo();
        vm.startPrank(alice);
        mUsdc.mint(alice, 50_000e8);

        mUsdc.approve(address(jwrapMusdc), 50_000e8);
        jwrapMusdc.wrap(50_000e8);
        assertEq(jwrapMusdc.balanceOf(alice), 50_000e8);
        jwrapMusdc.approve(address(jusdBank), 50_000e8);
        jusdBank.deposit(alice, address(jwrapMusdc), 50_000e8, alice);
        assertEq(jwrapMusdc.mUSDCBalanceOf(alice), 50_000e8);
        jusdBank.withdraw(address(jwrapMusdc), 50_000e8, alice, false);
        assertEq(jwrapMusdc.mUSDCBalanceOf(alice), 50_000e8);
        jwrapMusdc.claimReward();
        assertEq(well.balanceOf(alice), 1e18);
        assertEq(usdc.balanceOf(alice), 1e6);

        jwrapMusdc.transfer(bob, 50_000e8);
        assertEq(well.balanceOf(alice), 2e18);
        assertEq(usdc.balanceOf(alice), 2e6);
        assertEq(jwrapMusdc.mUSDCBalanceOf(alice), 0);
        assertEq(jwrapMusdc.mUSDCBalanceOf(bob), 50_000e8);
        assertEq(jwrapMusdc.balanceOf(alice), 0);
        assertEq(jwrapMusdc.balanceOf(bob), 50_000e8);
    }

    function testDepositJwrapTokenToBank() public {
        setUpMtokenInfo();
        vm.startPrank(alice);
        mUsdc.mint(alice, 50_000e8);

        mUsdc.approve(address(jwrapMusdc), 50_000e8);
        jwrapMusdc.depositAndWrap(50_000e8);
        assertEq(jwrapMusdc.mUSDCBalanceOf(alice), 50_000e8);
        assertEq(jusdBank.getDepositBalance(address(jwrapMusdc), alice), 50_000e8);
        jusdBank.withdraw(address(jwrapMusdc), 50_000e8, alice, false);
        assertEq(jwrapMusdc.mUSDCBalanceOf(alice), 50_000e8);
        jwrapMusdc.claimReward();
        assertEq(well.balanceOf(alice), 1e18);
        assertEq(usdc.balanceOf(alice), 1e6);
    }

    function testLiquidateJwrap() public {
        setUpMtokenInfo();
        vm.startPrank(alice);
        mUsdc.mint(alice, 50_000e8);

        mUsdc.approve(address(jwrapMusdc), 50_000e8);
        jwrapMusdc.wrap(50_000e8);
        assertEq(jwrapMusdc.balanceOf(alice), 50_000e8);
        jwrapMusdc.approve(address(jusdBank), 50_000e8);
        jusdBank.deposit(alice, address(jwrapMusdc), 50_000e8, alice);
        assertEq(jwrapMusdc.mUSDCBalanceOf(alice), 50_000e8);
        jusdBank.borrow(900e6, alice, false);
        vm.stopPrank();

        jusdBank.updateReserveParam(address(jwrapMusdc), 5e17, 20_000_000e8, 4_000_000e8, 100_000e6);
        jusdBank.updateRiskParam(address(jwrapMusdc), 6e17, 2e16, 3e16);
        jwrapMusdc.setFlashloan(address(flashLiquidateJwrapMUSDC));
        bool safe = jusdBank.isAccountSafe(alice);
        assertEq(safe, false);

        vm.startPrank(bob);
        bytes memory param = abi.encode(bob, 1000e6);
        bytes memory afterParam = abi.encode(address(flashLiquidateJwrapMUSDC), param);
        jusdBank.liquidate(alice, address(jwrapMusdc), bob, 50_000e8, afterParam, 2e14);
    }
}
