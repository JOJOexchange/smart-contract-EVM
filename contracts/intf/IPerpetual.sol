/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;

// Perpetual
// 1. report - balanceOf
// 2. modif - trade
// 3. modify - liquidate
// 4. modify - changeCredit

interface IPerpetual {
    function balanceOf(address trader)
        external
        view
        returns (int256 paperAmount, int256 credit);

    function trade(
        bytes calldata tradeData
    ) external;

    function liquidate(address liquidatedTrader, uint256 requestPaperAmount)
        external;

    function changeCredit(address trader, int256 amount) external;
}
