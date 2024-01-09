/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../init/TradingInit.sol";
import "../utils/Checkers.sol";
import "../../src/FundingRateUpdateLimiter.sol";

// Check dealer's fundingRate
contract FundingRateTest is Checkers {
    function deposit() public {
        vm.startPrank(traders[0]);
        jojoDealer.deposit(0, 1_000_000e6, traders[0]);
        vm.stopPrank();
        vm.startPrank(traders[1]);
        jojoDealer.deposit(0, 1_000_000e6, traders[1]);
        vm.stopPrank();
    }

    function testRate0() public {
        deposit();
        vm.startPrank(traders[0]);
        cheats.expectRevert("JOJO_INVALID_FUNDING_RATE_KEEPER");
        address[] memory perps = new address[](2);
        perps[0] = address(perpList[0]);
        perps[1] = address(perpList[1]);
        int256[] memory rates = new int256[](2);
        rates[0] = 0;
        rates[1] = 0;
        jojoDealer.updateFundingRate(perps, rates);
        vm.stopPrank();
        assertEq(jojoDealer.getFundingRate(address(perpList[0])), 0);
        trade(1e18, -30_000e6, -1e18, 30_000e6, 1e18, 1e18, address(perpList[0]));
        (int256 trader0Paper, int256 trader0Credit) = perpList[0].balanceOf(traders[0]);
        (int256 trader1Paper, int256 trader1Credit) = perpList[0].balanceOf(traders[1]);
        assertEq(trader0Paper, 1e18);
        assertEq(trader0Credit, -30_015e6);
        assertEq(trader1Paper, -1e18);
        assertEq(trader1Credit, 29_997e6);
    }

    function testRateBigger0() public {
        deposit();
        address[] memory perps = new address[](2);
        perps[0] = address(perpList[0]);
        perps[1] = address(perpList[1]);
        int256[] memory rates = new int256[](2);
        rates[0] = 1e6;
        rates[1] = 1e6;
        jojoDealer.updateFundingRate(perps, rates);
        vm.stopPrank();
        assertEq(jojoDealer.getFundingRate(address(perpList[0])), 1e6);
        trade(1e18, -30_000e6, -1e18, 30_000e6, 1e18, 1e18, address(perpList[0]));
        (int256 trader0Paper, int256 trader0Credit) = perpList[0].balanceOf(traders[0]);
        (int256 trader1Paper, int256 trader1Credit) = perpList[0].balanceOf(traders[1]);
        assertEq(trader0Paper, 1e18);
        assertEq(trader0Credit, -30_015e6);
        assertEq(trader1Paper, -1e18);
        assertEq(trader1Credit, 29_997e6);
    }

    function testMultiMarket() public {
        deposit();
        trade(1e18, -30_000e6, -1e18, 30_000e6, 1e18, 1e18, address(perpList[0]));
        trade(1e18, -2000e6, -1e18, 2000e6, 1e18, 1e18, address(perpList[1]));
        trade(-1e18, 2000e6, 1e18, -2000e6, 1e18, 1e18, address(perpList[1]));
    }

    function testRateSmaller0() public {
        deposit();
        address[] memory perps = new address[](2);
        perps[0] = address(perpList[0]);
        perps[1] = address(perpList[1]);
        int256[] memory rates = new int256[](2);
        rates[0] = -1e6;
        rates[1] = -1e6;
        jojoDealer.updateFundingRate(perps, rates);
        vm.stopPrank();
        assertEq(jojoDealer.getFundingRate(address(perpList[0])), -1e6);
        trade(1e18, -30_000e6, -1e18, 30_000e6, 1e18, 1e18, address(perpList[0]));
        (int256 trader0Paper, int256 trader0Credit) = perpList[0].balanceOf(traders[0]);
        (int256 trader1Paper, int256 trader1Credit) = perpList[0].balanceOf(traders[1]);
        assertEq(trader0Paper, 1e18);
        assertEq(trader0Credit, -30_015e6);
        assertEq(trader1Paper, -1e18);
        assertEq(trader1Credit, 29_997e6);
    }

    function testRateIncrease() public {
        deposit();
        address[] memory perps = new address[](2);
        perps[0] = address(perpList[0]);
        perps[1] = address(perpList[1]);
        int256[] memory rates = new int256[](2);
        rates[0] = -1e6;
        rates[1] = -1e6;
        jojoDealer.updateFundingRate(perps, rates);
        vm.stopPrank();
        trade(1e18, -30_000e6, -1e18, 30_000e6, 1e18, 1e18, address(perpList[0]));
        rates[0] = 5e5;
        jojoDealer.updateFundingRate(perps, rates);
        (int256 trader0Paper, int256 trader0Credit) = perpList[0].balanceOf(traders[0]);
        (int256 trader1Paper, int256 trader1Credit) = perpList[0].balanceOf(traders[1]);
        assertEq(trader0Paper, 1e18);
        assertEq(trader0Credit, -30_013_500_000);
        assertEq(trader1Paper, -1e18);
        assertEq(trader1Credit, 29_995_500_000);
    }

    function testRateRevert() public {
        deposit();
        address[] memory perps = new address[](2);
        perps[0] = address(perpList[0]);
        perps[1] = address(perpList[1]);
        int256[] memory rates = new int256[](1);
        rates[0] = -1e6;
        cheats.expectRevert("JOJO_ARRAY_LENGTH_NOT_SAME");
        jojoDealer.updateFundingRate(perps, rates);
    }

    function testLimiter() public {
        FundingRateUpdateLimiter limiter = new FundingRateUpdateLimiter(address(jojoDealer), 3);
        jojoDealer.setFundingRateKeeper(address(limiter));
        address[] memory perps = new address[](1);
        perps[0] = address(perpList[0]);
        int256[] memory rates = new int256[](1);
        rates[0] = 1e6;
        vm.warp(100_000_000);
        limiter.updateFundingRate(perps, rates);
        vm.warp(100_086_400);
        assertEq(limiter.getMaxChange(perps[0]), 2700e6);
        rates[0] = 2702e6;
        cheats.expectRevert("FUNDING_RATE_CHANGE_TOO_MUCH");
        limiter.updateFundingRate(perps, rates);
    }
}
