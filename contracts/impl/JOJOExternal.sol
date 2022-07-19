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

    // ========== events ==========

    event SetOperator(
        address indexed client,
        address indexed operator,
        bool isValid
    );

    // ========== fund related ==========

    /// @inheritdoc IDealer
    function deposit(
        uint256 primaryAmount,
        uint256 secondaryAmount,
        address to
    ) external nonReentrant {
        Funding.deposit(state, primaryAmount, secondaryAmount, to);
    }

    /// @inheritdoc IDealer
    function requestWithdraw(uint256 primaryAmount, uint256 secondaryAmount)
        external
        nonReentrant
    {
        Funding.requestWithdraw(state, primaryAmount, secondaryAmount);
    }

    /// @inheritdoc IDealer
    function executeWithdraw(address to, bool isInternal)
        external
        nonReentrant
    {
        Funding.executeWithdraw(state, to, isInternal);
    }

    /// @inheritdoc IDealer
    function isSafe(address trader) external view returns (bool safe) {
        return Liquidation._isSafe(state, trader);
    }

    /// @inheritdoc IDealer
    function getFundingRate(address perp) external view returns (int256) {
        return state.perpRiskParams[perp].fundingRate;
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
            .getLiquidateCreditAmount(
                state,
                perp,
                liquidatedTrader,
                requestPaperAmount
            );
        if (liqtorPaperChange != 0) {
            Trading._addPosition(state, perp, liquidator);
        }

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

    /// @inheritdoc IDealer
    function setOperator(address operator, bool isValid) external {
        state.operatorRegistry[msg.sender][operator] = isValid;
        emit SetOperator(msg.sender, operator, isValid);
    }
}
