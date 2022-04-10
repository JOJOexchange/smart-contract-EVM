/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;

interface IPerpetual {

    /// @notice The paper amount and credit amount of a certain trader
    /// @return paper positive when trader holds long position;
    /// negative when trader holds short position.
    /// @return credit not related to position direction or entry price,
    /// only used to calculate risk ratio and net value.
    function balanceOf(address trader)
        external
        view
        returns (int256 paper, int256 credit);

    /// @notice tradeData will be transfered to Dealer.
    /// and Perpetual will just execute the result
    function trade(bytes calldata tradeData) external;

    /// @notice Submit the paper amount you want to liquidate.
    /// But as the liquidation is public, there is no guarantee that 
    /// your request will be executed. 
    /// It is possible that someone else submitted a liquidation 
    /// request before you; or the user replenished the margin in time; 
    /// or the mark price moved.
    /// This function will help you liquidate as much as position size.
    /// @param  liquidatedTrader the trader you want to liquidate
    /// @param  requestPaper the size of position you want to take 
    /// positive if you want to liquidate a long position. negative if short.
    /// @param expectCredit the amount of credit you want to pay (when liquidate short)
    /// or receive (when liquidate long)
    /// @return liqtorPaperChange the final change of liquidator's paper amount
    /// @return liqtorCreditChange the final change of liquidator's credit amount
    function liquidate(
        address liquidatedTrader,
        int256 requestPaper,
        int256 expectCredit
    ) external returns (int256 liqtorPaperChange, int256 liqtorCreditChange);

    /// @notice can only be called by owner, used for accrual unrealized PNL
    function changeCredit(address trader, int256 amount) external;
}
