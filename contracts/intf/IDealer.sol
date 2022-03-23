/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;

// Dealer
// 1. trade - approveTrade
// 2. credit -  isSafe
// 3. funding - getFundingRatio
// 4. liquidation - getLiquidateCreditAmount

interface IDealer {
    function approveTrade(address orderSender, bytes calldata tradeData)
        external
        returns (
            address[] memory traderList,
            int256[] memory paperChangeList,
            int256[] memory creditChangeList
        );

    function isSafe(address trader) external returns (bool);

    function getFundingRatio(address perpetualAddress)
        external
        view
        returns (int256);

    // if the brokenTrader in long position, liquidatePaperAmount < 0 and liquidateCreditAmount > 0;
    function getLiquidateCreditAmount(
        address brokenTrader,
        int256 liquidatePaperAmount
    ) external returns (int256 paperAmount, int256 creditAmount);

    function positionClear(
        address trader
    ) external;
}
