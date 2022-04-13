/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;

// Dealer
// 1. trade - approveTrade
// 2. credit -  isSafe
// 3. funding - getFundingRate
// 4. liquidation - getLiquidateCreditAmount

interface IDealer {

    function requestWithdraw(uint256 primaryAmount, uint256 secondaryAmount) external;

    function executeWithdraw(address to) external;

    function approveTrade(address orderSender, bytes calldata tradeData)
        external
        returns (
            address[] memory traderList,
            int256[] memory paperChangeList,
            int256[] memory creditChangeList
        );

    function isSafe(address trader) external returns (bool);

    function isPositionSafe(address trader, address perp) external view returns (bool safe);

    function getFundingRate(address perpetualAddress)
        external
        view
        returns (int256);

    // lt = liquidatedTrader who is broken
    // liquidator is the one wants take over lt's position
    function requestLiquidate(
        address liquidator,
        address liquidatedTrader,
        int256 requestPaperAmount
    )
        external
        returns (
            int256 liqtorPaperChange,
            int256 liqtorCreditChange,
            int256 liqedPaperChange,
            int256 liqedCreditChange
        );

    function positionClear(address trader) external;
}
