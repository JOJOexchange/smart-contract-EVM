/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../init/JUSDBankInit.t.sol";

// Check jusd exchange
contract JUSDExchangeTest is JUSDBankInitTest {
    function testExchangeSuccess() public {
        vm.startPrank(alice);
        usdc.mint(alice, 1000e6);
        usdc.approve(address(jusdExchange), 1000e6);
        jusdExchange.buyJUSD(1000e6, alice);
        assertEq(jusd.balanceOf(alice), 1000e6);
        assertEq(usdc.balanceOf(alice), 0);
    }

    function testExchangeSuccessClose() public {
        jusdExchange.closeExchange();
        vm.startPrank(alice);
        usdc.mint(alice, 1000e6);
        usdc.approve(address(jusdExchange), 1000e6);
        cheats.expectRevert("NOT_ALLOWED_TO_EXCHANGE");
        jusdExchange.buyJUSD(1000e6, alice);
        vm.stopPrank();
        jusdExchange.openExchange();
        vm.startPrank(alice);
        usdc.approve(address(jusdExchange), 1000e6);
        jusdExchange.buyJUSD(1000e6, alice);
    }
}
