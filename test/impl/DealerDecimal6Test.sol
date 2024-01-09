/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../init/TradingInit.sol";

// Check dealer's decimal
contract Decimal6Test is TradingInit {
    function deposit() public {
        vm.startPrank(traders[0]);
        jojoDealer.deposit(0, 10_000e6, traders[0]);
        vm.stopPrank();
        vm.startPrank(traders[1]);
        jojoDealer.deposit(0, 10_000e6, traders[1]);
        vm.stopPrank();
    }

    function testBalanceCheck() public {
        deposit();
        trade(1e18, -30_000e6, -1e18, 30_000e6, 1e18, 1e18, address(perpList[0]));
        (, uint256 secondaryCredit0,,,) = jojoDealer.getCreditOf(traders[0]);
        (, uint256 secondaryCredit1,,,) = jojoDealer.getCreditOf(traders[1]);
        assertEq(secondaryCredit0, 10_000e6);
        assertEq(secondaryCredit1, 10_000e6);
        (int256 netValue0, uint256 exposure0,,) = jojoDealer.getTraderRisk(traders[0]);
        (int256 netValue1, uint256 exposure1,,) = jojoDealer.getTraderRisk(traders[1]);
        assertEq(netValue0, 9985e6);
        assertEq(netValue1, 9997e6);
        assertEq(exposure0, 30_000e6);
        assertEq(exposure1, 30_000e6);
    }

    function testLiqPrice() public {
        deposit();
        jojoDealer.getLiquidationPrice(traders[0], address(perpList[0]));
        trade(1e18, -30_000e6, -1e18, 30_000e6, 1e18, 1e18, address(perpList[0]));
        uint256 liquidationPrice0 = jojoDealer.getLiquidationPrice(traders[0], address(perpList[0]));
        uint256 liquidationPrice1 = jojoDealer.getLiquidationPrice(traders[1], address(perpList[0]));
        jojoDealer.getLiquidationPrice(traders[0], address(perpList[1]));
        assertEq(liquidationPrice0, 20_634_020_618);
        assertEq(liquidationPrice1, 38_832_038_834);
        priceSourceList[0].setMarkPrice(20_000e6);
        assertEq(jojoDealer.isSafe(traders[0]), false);
        priceSourceList[0].setMarkPrice(40_000e6);
        assertEq(jojoDealer.isSafe(traders[1]), false);
    }

    function testSecondaryAssetExist() public {
        deposit();
        trade(1e18, -30_000e6, -1e18, 30_000e6, 1e18, 1e18, address(perpList[0]));
        TestERC20 usdw = new TestERC20("USDW", "USDW", 12);
        cheats.expectRevert("JOJO_SECONDARY_ASSET_ALREADY_EXIST");
        jojoDealer.setSecondaryAsset(address(usdw));
    }
}
