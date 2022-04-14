/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./JOJOStorage.sol";
import "../lib/Liquidation.sol";
import "../lib/Trading.sol";
import "../utils/Errors.sol";

contract JOJOView is JOJOStorage {
    // ========== simple read state ==========

    function getPrimaryAsset() external view returns (address primaryAsset) {
        primaryAsset = state.primaryAsset;
    }

    function getSecondaryAsset()
        external
        view
        returns (address secondaryAsset)
    {
        secondaryAsset = state.secondaryAsset;
    }

    function getRiskParams(address perpetualAddress)
        external
        view
        returns (Types.RiskParams memory params)
    {
        params = state.perpRiskParams[perpetualAddress];
    }

    function getFundingRate(address perpetualAddress)
        external
        view
        returns (int256)
    {
        return state.perpRiskParams[perpetualAddress].fundingRate;
    }

    function getRegisteredPerp() external view returns (address[] memory) {
        return state.registeredPerp;
    }

    function getPositions(address trader)
        external
        view
        returns (address[] memory)
    {
        return state.openPositions[trader];
    }

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

    // ========== risk related ==========

    function isSafe(address trader) external view returns (bool safe) {
        return Liquidation._isSafe(state, trader);
    }

    function isPositionSafe(address trader, address perp)
        external
        view
        returns (bool safe)
    {
        (int256 paper, ) = IPerpetual(perp).balanceOf(trader);
        if (paper == 0) {
            return true;
        }
        return Liquidation._isPositionSafe(state, trader, perp);
    }

    function getTraderRisk(address trader)
        external
        view
        returns (int256 netValue, uint256 exposure)
    {
        int256 positionNetValue;
        (positionNetValue, exposure, ) = Liquidation._getTotalExposure(
            state,
            trader
        );
        netValue =
            positionNetValue +
            state.primaryCredit[trader] +
            int256(state.secondaryCredit[trader]);
    }

    // ========== liquidation related ==========

    function getLiquidationPrice(address trader, address perp)
        external
        view
        returns (uint256 liquidationPrice)
    {
        // return 0 if the trader can not be liquidated
        return Liquidation._getLiquidationPrice(state, trader, perp);
    }

    function getLiquidationCost(
        address perp,
        address liquidatedTrader,
        int256 requestPaperAmount
    )
        external
        view
        returns (int256 liqtorPaperChange, int256 liqtorCreditChange)
    {
        // view version for requestLiquidate
        (liqtorPaperChange, liqtorCreditChange, ) = Liquidation
            ._getLiquidateCreditAmount(
                state,
                perp,
                liquidatedTrader,
                requestPaperAmount
            );
    }

    // ========== order related ==========

    function getOrderHash(Types.Order memory order)
        external
        view
        returns (bytes32 orderHash)
    {
        orderHash = Trading._getOrderHash(state.domainSeparator, order);
    }

    function getOrderFilledAmount(bytes32 orderHash)
        external
        view
        returns (uint256 filledAmount)
    {
        filledAmount = state.orderFilledPaperAmount[orderHash];
    }
}
