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
import "../lib/Trading.sol";

abstract contract JOJOView is JOJOStorage, IDealer {
    // ========== simple read state ==========

    /// @param perp the address of perpetual contract market
    function getRiskParams(address perp)
        external
        view
        returns (Types.RiskParams memory params)
    {
        params = state.perpRiskParams[perp];
    }

    /// @notice Return all registered perpetual contract market.
    function getAllRegisteredPerps() external view returns (address[] memory) {
        return state.registeredPerp;
    }

    /// @notice Return mark price of a perpetual market.
    /// price is a 1e18 based decimal.
    function getMarkPrice(address perp) external view returns (uint256) {
        return Liquidation.getMarkPrice(state, perp);
    }

    /// @notice Get all open positions of the trader.
    function getPositions(address trader)
        external
        view
        returns (address[] memory)
    {
        return state.openPositions[trader];
    }

    /// @notice Return the credit details of the trader.
    /// You cannot use credit as net value or net margin of a trader.
    /// The net value of positions would also be included.
    function getCreditOf(address trader)
        external
        view
        returns (
            int256 primaryCredit,
            uint256 secondaryCredit,
            uint256 pendingPrimaryWithdraw,
            uint256 pendingSecondaryWithdraw,
            uint256 executionTimestamp
        )
    {
        primaryCredit = state.primaryCredit[trader];
        secondaryCredit = state.secondaryCredit[trader];
        pendingPrimaryWithdraw = state.pendingPrimaryWithdraw[trader];
        pendingSecondaryWithdraw = state.pendingSecondaryWithdraw[trader];
        executionTimestamp = state.withdrawExecutionTimestamp[trader];
    }

    function isOrderSenderValid(address orderSender)
        external
        view
        returns (bool)
    {
        return state.validOrderSender[orderSender];
    }

    function isOperatorValid(address client, address operator)
        external
        view
        returns (bool)
    {
        return state.operatorRegistry[client][operator];
    }

    // ========== liquidation related ==========

    /// @inheritdoc IDealer
    function isSafe(address trader) external view returns (bool safe) {
        return Liquidation._isSafe(state, trader);
    }

    /// @inheritdoc IDealer
    function isAllSafe(address[] calldata traderList)
        external
        view
        returns (bool safe)
    {
        return Liquidation._isAllSafe(state, traderList);
    }

    /// @inheritdoc IDealer
    function getFundingRate(address perp) external view returns (int256) {
        return IPerpetual(perp).getFundingRate();
    }

    /// @notice Get the risk profile data of a trader.
    /// @return netValue net value of trader including credit amount
    /// @return exposure open position value of the trader across all markets
    function getTraderRisk(address trader)
        external
        view
        returns (
            int256 netValue,
            uint256 exposure,
            uint256 maintenanceMargin
        )
    {
        int256 positionNetValue;
        (positionNetValue, exposure, maintenanceMargin) = Liquidation
            .getTotalExposure(state, trader);
        netValue =
            positionNetValue +
            state.primaryCredit[trader] +
            int256(state.secondaryCredit[trader]);
    }

    /// @notice Get liquidation price of a position
    /// @dev This function is for directional use. The margin of error is typically
    /// within 10 wei.
    /// @return liquidationPrice equals 0 if there is no liquidation price.
    function getLiquidationPrice(address trader, address perp)
        external
        view
        returns (uint256 liquidationPrice)
    {
        return Liquidation.getLiquidationPrice(state, trader, perp);
    }

    /// @notice a view version of requestLiquidation, liquidators can use
    /// this function to check how much you have to pay in advance.
    function getLiquidationCost(
        address perp,
        address liquidatedTrader,
        int256 requestPaperAmount
    )
        external
        view
        returns (int256 liqtorPaperChange, int256 liqtorCreditChange)
    {
        (liqtorPaperChange, liqtorCreditChange, ) = Liquidation
            .getLiquidateCreditAmount(
                state,
                perp,
                liquidatedTrader,
                requestPaperAmount
            );
    }

    // ========== order related ==========

    /// @notice Get filled paper amount of an order to avoid double matching.
    /// @return filledAmount includes paper amount
    function getOrderFilledAmount(bytes32 orderHash)
        external
        view
        returns (uint256 filledAmount)
    {
        filledAmount = state.orderFilledPaperAmount[orderHash];
    }
}
