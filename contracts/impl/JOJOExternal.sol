/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./JOJOStorage.sol";
import "../utils/Errors.sol";
import "../intf/IDealer.sol";
import "../lib/Liquidation.sol";
import "../lib/Funding.sol";
import "../lib/Trading.sol";

abstract contract JOJOExternal is JOJOStorage, IDealer {
    using SafeERC20 for IERC20;

    // ========== fund related ==========

    /// @notice Deposit fund to get credit for trading
    /// @param primaryAmount is the amount of primary asset you want to withdraw.
    /// @param secondaryAmount is the amount of secondary asset you want to withdraw.
    /// @param to Please be careful. If you pass in others' addresses,
    /// the credit will be added to that address directly.
    function deposit(
        uint256 primaryAmount,
        uint256 secondaryAmount,
        address to
    ) external nonReentrant {
        Funding._deposit(state, primaryAmount, secondaryAmount, to);
    }

    /// @inheritdoc IDealer
    function requestWithdraw(uint256 primaryAmount, uint256 secondaryAmount)
        external
        nonReentrant
    {
        Funding._requestWithdraw(state, primaryAmount, secondaryAmount);
    }

    /// @inheritdoc IDealer
    function executeWithdraw(address to) external nonReentrant {
        Funding._executeWithdraw(state, to);
    }

    // ========== registered perpetual only ==========

    /// @inheritdoc IDealer
    function approveTrade(address orderSender, bytes calldata tradeData)
        external
        returns (
            address[] memory, // traderList
            int256[] memory, // paperChangeList
            int256[] memory // creditChangeList
        )
    {
        Types.MatchResult memory result = Trading._approveTrade(
            state,
            orderSender,
            tradeData
        );

        // charge fee
        state.primaryCredit[orderSender] += result.orderSenderFee;
        // if orderSender pay traders, check if orderSender is safe
        if (result.orderSenderFee < 0) {
            require(
                Liquidation._isSolidSafe(state, orderSender),
                Errors.ORDER_SENDER_NOT_SAFE
            );
        }

        return (
            result.traderList,
            result.paperChangeList,
            result.creditChangeList
        );
    }

    /// @inheritdoc IDealer
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
        )
    {
        address perp = msg.sender;
        uint256 insuranceFee;
        (liqtorPaperChange, liqtorCreditChange, insuranceFee) = Liquidation
            ._getLiquidateCreditAmount(
                state,
                perp,
                liquidatedTrader,
                requestPaperAmount
            );
        state.primaryCredit[state.insurance] += int256(insuranceFee);

        // liquidated trader balance change
        liqedCreditChange = liqtorCreditChange * -1 - int256(insuranceFee);
        liqedPaperChange = liqtorPaperChange * -1;

        // events
        uint256 ltSN = state.positionSerialNum[liquidatedTrader][perp];
        uint256 liquidatorSN = state.positionSerialNum[liquidator][perp];
        emit Liquidation.BeingLiquidated(
            perp,
            liquidatedTrader,
            liqtorPaperChange,
            liqtorCreditChange,
            ltSN
        );
        emit Liquidation.JoinLiquidation(
            perp,
            liquidator,
            liquidatedTrader,
            liqtorPaperChange,
            liqtorCreditChange,
            liquidatorSN
        );
        emit Liquidation.InsuranceChange(
            perp,
            liquidatedTrader,
            int256(insuranceFee)
        );
    }

    /// @inheritdoc IDealer
    function positionClear(address trader) external {
        Trading._positionClear(state, trader);
    }
}
