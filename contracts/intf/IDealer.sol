pragma solidity 0.8.9;

// Dealer
// 1. trade - approveTrade
// 2. credit -  isSafe
// 3. funding - getFundingRatio
// 4. liquidation - getLiquidateCreditAmount

interface IDealer {
    function approveTrade(address sender, bytes calldata tradeData)
        external
        returns (
            address taker,
            address[] memory makerList,
            int256[] memory tradePaperAmountList,
            int256[] memory tradeCreditAmountList
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
}
