/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../init/TradingInit.sol";
import "../utils/Checkers.sol";
import "../../src/FundingRateUpdateLimiter.sol";

/*
    Test cases list
    - check position
      - single position check
      - multi position check
      - position independent safe check
      - all position pnl summary
    - being liquidated
      - caused by funding rate
      - caused by mark price change
    - liquidate price
        - single liquidation > total position
        - single liquidation = total position
        - single liquidation < total position
        - change with mark price
    - execute liquidation
        - balance
        - insurance fee
        - bad debt
    - return to safe before liquidate all position
        - partially liquidated
        - mark price changed
        - funding rate changed
    - handle bad debt

    Revert cases
    - can not liquidate safe trader
    - liquidator not safe
    - self liquidation
    - safe account can not be handleDebt
    - can not handle debt before liquidation finished
*/

// Check dealer's liquidation
contract LiquidationTest is Checkers {
    // trader2 is liquidator
    function deposit() public {
        vm.startPrank(traders[0]);
        jojoDealer.deposit(0, 5000e6, traders[2]);
        jojoDealer.deposit(5000e6, 5000e6, traders[0]);
        vm.stopPrank();

        vm.startPrank(traders[1]);
        jojoDealer.deposit(5000e6, 5000e6, traders[1]);
        vm.stopPrank();
    }

    function openPositionForExcuteTest() public {
        trade(1e18, -30_000e6, -1e18, 30_000e6, 1e18, 1e18, address(perpList[0]));
        priceSourceList[0].setMarkPrice(20_600e6);
    }

    function testSingleCheckPosition() public {
        deposit();
        trade(1e18, -30_000e6, -1e18, 30_000e6, 1e18, 1e18, address(perpList[0]));
        priceSourceList[0].setMarkPrice(39_000e6);
        assertEq(jojoDealer.isSafe(traders[0]), true);
        assertEq(jojoDealer.isSafe(traders[1]), false);
        priceSourceList[0].setMarkPrice(20_000e6);
        assertEq(jojoDealer.isSafe(traders[0]), false);
        assertEq(jojoDealer.isSafe(traders[1]), true);
    }

    function testMultiCheckPosition() public {
        deposit();
        trade(1e18, -30_000e6, -1e18, 30_000e6, 1e18, 1e18, address(perpList[0]));
        trade(10e18, -20_000e6, -10e18, 20_000e6, 10e18, 10e18, address(perpList[1]));
        priceSourceList[0].setMarkPrice(21_676e6);
        assertEq(jojoDealer.isSafe(traders[0]), true);
        priceSourceList[0].setMarkPrice(21_675e6);
        assertEq(jojoDealer.isSafe(traders[0]), false);

        priceSourceList[0].setMarkPrice(37_859e6);
        assertEq(jojoDealer.isSafe(traders[1]), true);
        priceSourceList[0].setMarkPrice(37_860e6);
        assertEq(jojoDealer.isSafe(traders[1]), false);

        priceSourceList[0].setMarkPrice(30_000e6);

        priceSourceList[1].setMarkPrice(1150e6);
        assertEq(jojoDealer.isSafe(traders[0]), true);
        priceSourceList[1].setMarkPrice(1149e6);
        assertEq(jojoDealer.isSafe(traders[0]), false);

        priceSourceList[1].setMarkPrice(2770e6);
        assertEq(jojoDealer.isSafe(traders[1]), true);
        priceSourceList[1].setMarkPrice(2771e6);
        assertEq(jojoDealer.isSafe(traders[1]), false);
    }

    function testCasedByFundingRate() public {
        deposit();
        trade(10e18, -300_000e6, -10e18, 300_000e6, 10e18, 10e18, address(perpList[0]));
        address[] memory perps = new address[](1);
        perps[0] = address(perpList[0]);
        int256[] memory rates = new int256[](1);
        rates[0] = -84e6;
        jojoDealer.updateFundingRate(perps, rates);
        assertEq(jojoDealer.isSafe(traders[0]), true);
        assertEq(jojoDealer.isSafe(traders[1]), true);

        rates[0] = -86e6;
        jojoDealer.updateFundingRate(perps, rates);

        assertEq(jojoDealer.isSafe(traders[0]), false);
        assertEq(jojoDealer.isSafe(traders[1]), true);

        rates[0] = 97e6;
        jojoDealer.updateFundingRate(perps, rates);
        assertEq(jojoDealer.isSafe(traders[0]), true);
        assertEq(jojoDealer.isSafe(traders[1]), true);

        rates[0] = 98e6;
        jojoDealer.updateFundingRate(perps, rates);
        assertEq(jojoDealer.isSafe(traders[0]), true);
        assertEq(jojoDealer.isSafe(traders[1]), false);
    }

    function testExecuteLiquidationOperatorCallLiquidation() public {
        deposit();
        openPositionForExcuteTest();
        vm.startPrank(traders[1]);
        cheats.expectRevert("JOJO_INVALID_LIQUIDATION_EXECUTOR");
        perpList[0].liquidate(traders[2], traders[1], 1e16, -500e6);
        vm.stopPrank();

        vm.startPrank(traders[2]);
        jojoDealer.setOperator(traders[1], true);
        vm.stopPrank();

        vm.startPrank(traders[1]);
        perpList[0].liquidate(traders[2], traders[0], 2e18, -50_000e6);
        checkCredit(insurance, 20_394e4, 0);
        checkCredit(traders[0], -482_494e4, 5000e6);
        (int256 paperLiquidator, int256 creditLiquidator) = perpList[0].balanceOf(traders[2]);
        (int256 paperLiquidated, int256 creditLiquidated) = perpList[0].balanceOf(traders[0]);
        assertEq(paperLiquidator, 1e18);
        assertEq(creditLiquidator, -20_394e6);
        assertEq(paperLiquidated, 0);
        assertEq(creditLiquidated, 0);
    }

    function testExecuteLiquidationBiggerTotalPosition() public {
        deposit();
        openPositionForExcuteTest();
        (int256 liqtorPaperChange, int256 liqtorCreditChange) =
            jojoDealer.getLiquidationCost(address(perpList[0]), traders[0], 2e18);
        assertEq(liqtorPaperChange, 1e18);
        assertEq(liqtorCreditChange, -20_394e6);
        vm.startPrank(traders[2]);
        perpList[0].liquidate(traders[2], traders[0], 2e18, -50_000e6);
        checkCredit(insurance, 20_394e4, 0);
        checkCredit(traders[0], -482_494e4, 5000e6);
        (int256 paperLiquidator, int256 creditLiquidator) = perpList[0].balanceOf(traders[2]);
        (int256 paperLiquidated, int256 creditLiquidated) = perpList[0].balanceOf(traders[0]);
        assertEq(paperLiquidator, 1e18);
        assertEq(creditLiquidator, -20_394e6);
        assertEq(paperLiquidated, 0);
        assertEq(creditLiquidated, 0);
    }

    function testExecuteLiquidationEqualTotalPosition() public {
        deposit();
        openPositionForExcuteTest();
        (int256 liqtorPaperChange, int256 liqtorCreditChange) =
            jojoDealer.getLiquidationCost(address(perpList[0]), traders[0], 1e18);
        assertEq(liqtorPaperChange, 1e18);
        assertEq(liqtorCreditChange, -20_394e6);
        vm.startPrank(traders[2]);
        perpList[0].liquidate(traders[2], traders[0], 1e18, -25_000e6);
        checkCredit(insurance, 20_394e4, 0);
        checkCredit(traders[0], -482_494e4, 5000e6);
        (int256 paperLiquidator, int256 creditLiquidator) = perpList[0].balanceOf(traders[2]);
        (int256 paperLiquidated, int256 creditLiquidated) = perpList[0].balanceOf(traders[0]);
        assertEq(paperLiquidator, 1e18);
        assertEq(creditLiquidator, -20_394e6);
        assertEq(paperLiquidated, 0);
        assertEq(creditLiquidated, 0);
    }

    function testExecuteLiquidationSmallerTotalPosition() public {
        deposit();
        openPositionForExcuteTest();
        (int256 liqtorPaperChange, int256 liqtorCreditChange) =
            jojoDealer.getLiquidationCost(address(perpList[0]), traders[0], 1e16);
        assertEq(liqtorPaperChange, 1e16);
        assertEq(liqtorCreditChange, -20_394e4);
        vm.startPrank(traders[2]);
        perpList[0].liquidate(traders[2], traders[0], 1e16, -250e6);
        checkCredit(insurance, 20_394e2, 0);
        checkCredit(traders[0], 5_000_000_000, 5000e6);
        (int256 paperLiquidator, int256 creditLiquidator) = perpList[0].balanceOf(traders[2]);
        (int256 paperLiquidated, int256 creditLiquidated) = perpList[0].balanceOf(traders[0]);
        assertEq(paperLiquidator, 1e16);
        assertEq(creditLiquidator, -20_394e4);
        assertEq(paperLiquidated, 990_000_000_000_000_000);
        assertEq(creditLiquidated, -29_813_099_400);

        cheats.expectRevert("LIQUIDATION_PRICE_PROTECTION");
        perpList[0].liquidate(traders[2], traders[0], 2e18, -40_000e6);
    }

    function testExecuteLiquidationBiggerTotalPositionShort() public {
        deposit();
        openPositionForExcuteTest();
        priceSourceList[0].setMarkPrice(39_000e6);
        (int256 liqtorPaperChange, int256 liqtorCreditChange) =
            jojoDealer.getLiquidationCost(address(perpList[0]), traders[1], -2e18);
        assertEq(liqtorPaperChange, -1e18);
        assertEq(liqtorCreditChange, 39_390e6);
        vm.startPrank(traders[2]);
        perpList[0].liquidate(traders[2], traders[1], -2e18, 50_000e6);
        checkCredit(insurance, 3939e5, 0);
        checkCredit(traders[1], -47_869e5, 5000e6);
        (int256 paperLiquidator, int256 creditLiquidator) = perpList[0].balanceOf(traders[2]);
        (int256 paperLiquidated, int256 creditLiquidated) = perpList[0].balanceOf(traders[1]);
        assertEq(paperLiquidator, -1e18);
        assertEq(creditLiquidator, 39_390e6);
        assertEq(paperLiquidated, 0);
        assertEq(creditLiquidated, 0);
    }

    function testExecuteLiquidationSmallerTotalPositionShort() public {
        deposit();
        openPositionForExcuteTest();
        priceSourceList[0].setMarkPrice(39_000e6);
        (int256 liqtorPaperChange, int256 liqtorCreditChange) =
            jojoDealer.getLiquidationCost(address(perpList[0]), traders[1], -1e16);
        assertEq(liqtorPaperChange, -1e16);
        assertEq(liqtorCreditChange, 393_900_000);
        vm.startPrank(traders[2]);

        cheats.expectRevert("LIQUIDATION_PRICE_PROTECTION");
        perpList[0].liquidate(traders[2], traders[1], -1e16, 400e6);

        perpList[0].liquidate(traders[2], traders[1], -1e16, 300e6);
        checkCredit(insurance, 3_939_000, 0);
        checkCredit(traders[1], 5000e6, 5000e6);
        (int256 paperLiquidator, int256 creditLiquidator) = perpList[0].balanceOf(traders[2]);
        (int256 paperLiquidated, int256 creditLiquidated) = perpList[0].balanceOf(traders[1]);
        assertEq(paperLiquidator, -1e16);
        assertEq(creditLiquidator, 393_900_000);
        assertEq(paperLiquidated, -99e16);
        assertEq(creditLiquidated, 29_599_161e3);
    }

    function testExecuteLiquidationBadDebt() public {
        deposit();
        openPositionForExcuteTest();
        priceSourceList[0].setMarkPrice(19_000e6);
        vm.startPrank(traders[2]);
        perpList[0].liquidate(traders[2], traders[0], 1e18, -50_000e6);
        checkCredit(traders[0], 0, 0);
        cheats.expectRevert("JOJO_ACCOUNT_IS_SAFE");
        perpList[0].liquidate(traders[2], traders[0], 1e18, -50_000e6);
        checkCredit(insurance, -6205e6, 5000e6);
    }

    function testPartiallyLiquidation() public {
        deposit();
        openPositionForExcuteTest();
        vm.startPrank(traders[2]);
        // revert for wrong paper amount
        cheats.expectRevert("JOJO_LIQUIDATION_REQUEST_AMOUNT_WRONG");
        jojoDealer.getLiquidationCost(address(perpList[0]), traders[0], -99e6);
        perpList[0].liquidate(traders[2], traders[0], 99e16, -50_000e6);
        bool isSafe = jojoDealer.isSafe(traders[0]);
        assertEq(isSafe, true);
    }

    function testCannotLiquidate() public {
        deposit();
        openPositionForExcuteTest();
        priceSourceList[0].setMarkPrice(22_000e6);
        vm.startPrank(traders[2]);
        cheats.expectRevert("JOJO_ACCOUNT_IS_SAFE");
        perpList[0].liquidate(traders[2], traders[0], 1e16, -500e6);
    }

    function testLiquidatorNotSafe() public {
        deposit();
        openPositionForExcuteTest();
        vm.startPrank(traders[2]);
        jojoDealer.requestWithdraw(traders[2], 0, 5000e6);
        jojoDealer.executeWithdraw(traders[2], traders[2], false, "");
        cheats.expectRevert("LIQUIDATOR_NOT_SAFE");
        perpList[0].liquidate(traders[2], traders[0], 1e16, -500e6);
    }

    function testselfLiquidate() public {
        deposit();
        openPositionForExcuteTest();
        vm.startPrank(traders[0]);
        cheats.expectRevert("JOJO_SELF_LIQUIDATION_NOT_ALLOWED");
        perpList[0].liquidate(traders[0], traders[0], 1e16, -500e6);
    }

    function testNotHaveCertainPosition() public {
        deposit();
        openPositionForExcuteTest();
        vm.startPrank(traders[2]);
        cheats.expectRevert("JOJO_TRADER_HAS_NO_POSITION");
        perpList[1].liquidate(traders[2], traders[0], 1e16, -500e6);
    }
}
