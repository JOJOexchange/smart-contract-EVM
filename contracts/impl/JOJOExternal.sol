/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./JOJOStorage.sol";
import "../utils/Errors.sol";
import "../lib/Liquidation.sol";
import "../lib/Funding.sol";
import "../lib/Trading.sol";

contract JOJOExternal is JOJOStorage {
    using SafeERC20 for IERC20;

    // ========== fund related ==========

    function deposit(
        uint256 primaryAmount,
        uint256 secondaryAmount,
        address to
    ) external nonReentrant {
        Funding._deposit(state, primaryAmount, secondaryAmount, to);
    }

    function requestWithdraw(uint256 primaryAmount, uint256 secondaryAmount)
        external
        nonReentrant
    {
        Funding._requestWithdraw(state, primaryAmount, secondaryAmount);
    }

    function executeWithdraw(address to) external nonReentrant {
        Funding._executeWithdraw(state, to);
    }

    // ========== registered perpetual only ==========

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

    function positionClear(address trader) external {
        Liquidation._positionClear(state, trader);
    }
}
