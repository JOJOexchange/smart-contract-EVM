/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "../init/JUSDBankInit.t.sol";
import "../mocks/MockController.sol";
import "../mocks/MockMUSDC.sol";
import "../../src/token/JwarpMUSDCFactory.sol";
import "../../src/FlashLoanLiquidateJwarpMUSDC.sol";

contract JwarpMtokenSubaccountTest is JUSDBankInitTest {
    MockMUSDC public mUsdc;
    TestERC20 public well;
    EmergencyOracle public jwarpMusdcOracle;
    JwarpMUSDCFactory public jwarpMusdc;
    MockController public mockController;
    FlashLoanLiquidateJwarpMUSDC public flashLiquidateJwarpMUSDC;

    function setUpMtokenInfo() public {
        mUsdc = new MockMUSDC("mUsdc", "mUsdc", 8, address(usdc));
        usdc.mint(address(mUsdc), 10_000e6);
        well = new TestERC20("well", "well", 18);
        mockController = new MockController(address(well), address(usdc));
        well.mint(address(mockController), 10e18);
        usdc.mint(address(mockController), 10e6);
        jwarpMusdc = new JwarpMUSDCFactory(
            address(mUsdc),
            address(mockController),
            address(well),
            address(usdc),
            address(jusdBank),
            "JwarpMusdc",
            "JwarpMusdc"
        );
        flashLiquidateJwarpMUSDC = new FlashLoanLiquidateJwarpMUSDC(
            address(jusdBank), address(jusdExchange), address(usdc), address(jusd), insurance, address(jwarpMusdc)
        );
        jwarpMusdcOracle = new EmergencyOracle("JwarpMusdc oracle");
        jwarpMusdcOracle.setMarkPrice(2e14);
        jusdBank.initReserve(
            // token
            address(jwarpMusdc),
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
            address(jwarpMusdcOracle)
        );
    }

    function testDepositJwarpToken() public {
        setUpMtokenInfo();
        vm.startPrank(alice);
        mUsdc.mint(alice, 50_000e8);

        mUsdc.approve(address(jwarpMusdc), 50_000e8);
        jwarpMusdc.warp(50_000e8);
        assertEq(jwarpMusdc.balanceOf(alice), 50_000e8);
        jwarpMusdc.approve(address(jusdBank), 50_000e8);
        jusdBank.deposit(alice, address(jwarpMusdc), 50_000e8, alice);
        assertEq(jwarpMusdc.mUSDCBalanceOf(alice), 50_000e8);
        jusdBank.withdraw(address(jwarpMusdc), 50_000e8, alice, false);
        assertEq(jwarpMusdc.mUSDCBalanceOf(alice), 50_000e8);
        jwarpMusdc.claimReward();
        assertEq(well.balanceOf(alice), 1e18);
        assertEq(usdc.balanceOf(alice), 1e6);

        jwarpMusdc.transfer(bob, 50_000e8);
        assertEq(well.balanceOf(alice), 2e18);
        assertEq(usdc.balanceOf(alice), 2e6);
        assertEq(jwarpMusdc.mUSDCBalanceOf(alice), 0);
        assertEq(jwarpMusdc.mUSDCBalanceOf(bob), 50_000e8);
        assertEq(jwarpMusdc.balanceOf(alice), 0);
        assertEq(jwarpMusdc.balanceOf(bob), 50_000e8);
    }

    function testLiquidateJwrap() public {
        setUpMtokenInfo();
        vm.startPrank(alice);
        mUsdc.mint(alice, 50_000e8);

        mUsdc.approve(address(jwarpMusdc), 50_000e8);
        jwarpMusdc.warp(50_000e8);
        assertEq(jwarpMusdc.balanceOf(alice), 50_000e8);
        jwarpMusdc.approve(address(jusdBank), 50_000e8);
        jusdBank.deposit(alice, address(jwarpMusdc), 50_000e8, alice);
        assertEq(jwarpMusdc.mUSDCBalanceOf(alice), 50_000e8);
        jusdBank.borrow(900e6, alice, false);
        vm.stopPrank();

        jusdBank.updateReserveParam(address(jwarpMusdc), 5e17, 20_000_000e8, 4_000_000e8, 100_000e6);
        jusdBank.updateRiskParam(address(jwarpMusdc), 6e17, 2e16, 3e16);
        jwarpMusdc.setFlashloan(address(flashLiquidateJwarpMUSDC));
        bool safe = jusdBank.isAccountSafe(alice);
        assertEq(safe, false);

        vm.startPrank(bob);
        bytes memory param = abi.encode(bob, 1000e6);
        bytes memory afterParam = abi.encode(address(flashLiquidateJwarpMUSDC), param);
        jusdBank.liquidate(alice, address(jwarpMusdc), bob, 50_000e8, afterParam, 2e14);
    }
}
