/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;

interface IDealer {
    /// @notice Submit withdrawal request, which can be executed after the timelock.
    /// @param primaryAmount is the amount of primary asset you want to withdraw.
    /// @param secondaryAmount is the amount of secondary asset you want to withdraw.
    function requestWithdraw(uint256 primaryAmount, uint256 secondaryAmount)
        external;

    /// @notice execute the withdrawal request.
    /// @param Be careful if you pass in others' addresses,
    /// because the fund will be transferred to this address directly.
    function executeWithdraw(address to) external;

    /// @notice help perpetual contract parse tradeData and return
    /// the types of balance changes should be made to each trader.
    /// @dev only perpetual contract can call this function
    /// @param orderSender is the one who submit tradeData.
    /// @param tradeData data contain orders, signatures and match info.
    function approveTrade(address orderSender, bytes calldata tradeData)
        external
        returns (
            address[] memory traderList,
            int256[] memory paperChangeList,
            int256[] memory creditChangeList
        );

    /// @notice check if the trader's cross margin ratio is safe.
    /// At lease one of the trader's open positions will be liquidated
    /// if return false, but we don't know which one.
    /// Normally, this function is used internally. If you want to monitor
    /// a certain position, please use isPositionSafe.
    function isSafe(address trader) external view returns (bool);

    /// @notice check if a certain position is safe. The position will
    /// be liquidated if return false.
    /// @param perp please pass in address of Perpetual.sol.
    /// This function will check the trader's position in this market.
    function isPositionSafe(address trader, address perp)
        external
        view
        returns (bool);

    /// @notice get funding rate of a perpetual market.
    /// Funding rate is a 1e18 based decimal.
    function getFundingRate(address perp) external view returns (int256);

    /// @notice when someone calls liquidate function at perpetual.sol, it 
    /// will call this function to know how to change balances.
    /// @dev only perpetual contract can call this function.
    /// liqtor is short for liquidator, liqed is short for liquidated trader.
    /// @param liquidator is the one who will take over positions.
    /// @param liquidatedTrader is the one who is being liquidated.
    /// @param requestPaperAmount is the size that the liquidator wants to take.
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

    /// @notice accrual realized pnl
    /// @dev only perpetual contract can call this function.
    function positionClear(address trader) external;
}
