/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../interfaces/internal/IPriceSource.sol";
import "../interfaces/IPerpetual.sol";
import "../libraries/SignedDecimalMath.sol";
import "../libraries/Errors.sol";
import "./Types.sol";
import "./Position.sol";

library Liquidation {
    using SignedDecimalMath for int256;

    // ========== events ==========

    event BeingLiquidated(
        address indexed perp,
        address indexed liquidatedTrader,
        int256 paperChange,
        int256 creditChange,
        uint256 positionSerialNum
    );

    event JoinLiquidation(
        address indexed perp,
        address indexed liquidator,
        address indexed liquidatedTrader,
        int256 paperChange,
        int256 creditChange,
        uint256 positionSerialNum
    );

    // emit when charge insurance fee from liquidated trader
    event ChargeInsurance(address indexed perp, address indexed liquidatedTrader, uint256 fee);

    event HandleBadDebt(address indexed liquidatedTrader, int256 primaryCredit, uint256 secondaryCredit);

    // ========== trader safety check ==========

    function getTotalExposure(
        Types.State storage state,
        address trader
    )
        public
        view
        returns (int256 netValue, uint256 exposure, uint256 initialMargin, uint256 maintenanceMargin)
    {
        int256 netPositionValue;
        // sum net value and exposure among all markets
        for (uint256 i = 0; i < state.openPositions[trader].length;) {
            (int256 paperAmount, int256 creditAmount) = IPerpetual(state.openPositions[trader][i]).balanceOf(trader);
            Types.RiskParams storage params = state.perpRiskParams[state.openPositions[trader][i]];
            int256 price = SafeCast.toInt256(IPriceSource(params.markPriceSource).getMarkPrice());

            netPositionValue += paperAmount.decimalMul(price) + creditAmount;
            uint256 exposureIncrement = paperAmount.decimalMul(price).abs();
            exposure += exposureIncrement;
            maintenanceMargin += (exposureIncrement * params.liquidationThreshold) / Types.ONE;
            initialMargin += (exposureIncrement * params.initialMarginRatio) / Types.ONE;
            unchecked {
                ++i;
            }
        }
        netValue = netPositionValue + state.primaryCredit[trader] + SafeCast.toInt256(state.secondaryCredit[trader]);
    }

    function _isMMSafe(Types.State storage state, address trader) internal view returns (bool) {
        (int256 netValue,,, uint256 maintenanceMargin) = getTotalExposure(state, trader);
        return netValue >= SafeCast.toInt256(maintenanceMargin);
    }

    function _isIMSafe(Types.State storage state, address trader) internal view returns (bool) {
        (int256 netValue,, uint256 initialMargin,) = getTotalExposure(state, trader);
        return netValue >= SafeCast.toInt256(initialMargin);
    }

    /// @notice More strict than _isIMSafe.
    /// Additional requirement: netPositionValue + primaryCredit >= 0
    /// used when traders transfer out primary credit.
    function _isSolidIMSafe(Types.State storage state, address trader) internal view returns (bool) {
        (int256 netValue,, uint256 initialMargin,) = getTotalExposure(state, trader);
        return netValue - SafeCast.toInt256(state.secondaryCredit[trader]) >= 0
            && netValue >= SafeCast.toInt256(initialMargin);
    }

    function _isAllMMSafe(Types.State storage state, address[] calldata traderList) internal view returns (bool) {
        for (uint256 i = 0; i < traderList.length;) {
            address trader = traderList[i];
            if (!_isMMSafe(state, trader)) {
                return false;
            }
            unchecked {
                ++i;
            }
        }
        return true;
    }

    /// @return liquidationPrice It should be considered as the position can never be
    /// liquidated (absolutely safe) or being liquidated at the present if return 0.
    function getLiquidationPrice(
        Types.State storage state,
        address trader,
        address perp
    )
        external
        view
        returns (uint256 liquidationPrice)
    {
        /*
            To avoid liquidation, we need:
            netValue >= maintenanceMargin

            We first calculate the maintenanceMargin for all other markets' positions.
            Let's call it maintenanceMargin'

            Then we have netValue of the account.
            Let's call it netValue'

            So we have:
                netValue' + paperAmount * price + creditAmount >= 
                maintenanceMargin' + abs(paperAmount) * price * liquidationThreshold

            if paperAmount > 0
                paperAmount * price * (1-liquidationThreshold) >= maintenanceMargin' - netValue' - creditAmount
                price >= (maintenanceMargin' - netValue' - creditAmount)/paperAmount/(1-liquidationThreshold)
                liqPrice = (maintenanceMargin' - netValue' - creditAmount)/paperAmount/(1-liquidationThreshold)

            if paperAmount < 0
                paperAmount * price * (1+liquidationThreshold) >= maintenanceMargin' - netValue' - creditAmount
                price <= (maintenanceMargin' - netValue' - creditAmount)/paperAmount/(1+liquidationThreshold)
                liqPrice = (maintenanceMargin' - netValue' - creditAmount)/paperAmount/(1+liquidationThreshold)

            Let's call 1±liquidationThreshold "multiplier"
            Then:
                liqPrice = (maintenanceMargin' - netValue' - creditAmount)/paperAmount/multiplier

            If liqPrice<0, it should be considered as the position can never be
            liquidated (absolutely safe) or being liquidated at the present if return 0.
        */
        int256 maintenanceMarginPrime;
        int256 netValuePrime = state.primaryCredit[trader] + SafeCast.toInt256(state.secondaryCredit[trader]);
        for (uint256 i = 0; i < state.openPositions[trader].length;) {
            address p = state.openPositions[trader][i];
            if (perp != p) {
                (int256 paperAmountPrime, int256 creditAmountPrime) = IPerpetual(p).balanceOf(trader);
                Types.RiskParams storage params = state.perpRiskParams[p];
                int256 price = SafeCast.toInt256(IPriceSource(params.markPriceSource).getMarkPrice());
                netValuePrime += paperAmountPrime.decimalMul(price) + creditAmountPrime;
                maintenanceMarginPrime += SafeCast.toInt256(
                    (paperAmountPrime.decimalMul(price).abs() * params.liquidationThreshold) / Types.ONE
                );
            }
            unchecked {
                ++i;
            }
        }
        (int256 paperAmount, int256 creditAmount) = IPerpetual(perp).balanceOf(trader);
        if (paperAmount == 0) {
            return 0;
        }
        int256 multiplier = paperAmount > 0
            ? SafeCast.toInt256(Types.ONE - state.perpRiskParams[perp].liquidationThreshold)
            : SafeCast.toInt256(Types.ONE + state.perpRiskParams[perp].liquidationThreshold);
        int256 liqPrice =
            (maintenanceMarginPrime - netValuePrime - creditAmount).decimalDiv(paperAmount).decimalDiv(multiplier);
        return liqPrice < 0 ? 0 : uint256(liqPrice);
    }

    /// @notice Using a fixed discount price model.
    /// Charge fee from liquidated trader.
    /// Will limit you liquidation request to the position size.
    function getLiquidateCreditAmount(
        Types.State storage state,
        address perp,
        address liquidatedTrader,
        int256 requestPaperAmount
    )
        public
        view
        returns (int256 liqtorPaperChange, int256 liqtorCreditChange, uint256 insuranceFee)
    {
        // can not liquidate a safe trader
        require(!_isMMSafe(state, liquidatedTrader), Errors.ACCOUNT_IS_SAFE);

        // calculate and limit the paper change to the position size
        (int256 brokenPaperAmount,) = IPerpetual(perp).balanceOf(liquidatedTrader);
        require(brokenPaperAmount != 0, Errors.TRADER_HAS_NO_POSITION);
        require(requestPaperAmount * brokenPaperAmount > 0, Errors.LIQUIDATION_REQUEST_AMOUNT_WRONG);
        liqtorPaperChange = requestPaperAmount.abs() > brokenPaperAmount.abs() ? brokenPaperAmount : requestPaperAmount;

        // get price
        Types.RiskParams storage params = state.perpRiskParams[perp];
        uint256 price = IPriceSource(params.markPriceSource).getMarkPrice();
        uint256 priceOffset = (price * params.liquidationPriceOff) / Types.ONE;
        price = liqtorPaperChange > 0 ? price - priceOffset : price + priceOffset;

        // calculate credit change
        liqtorCreditChange = -1 * liqtorPaperChange.decimalMul(SafeCast.toInt256(price));
        insuranceFee = (liqtorCreditChange.abs() * params.insuranceFeeRate) / Types.ONE;
    }

    /// @notice execute a liquidation request
    function requestLiquidation(
        Types.State storage state,
        address perp,
        address executor,
        address liquidator,
        address liquidatedTrader,
        int256 requestPaperAmount
    )
        external
        returns (int256 liqtorPaperChange, int256 liqtorCreditChange, int256 liqedPaperChange, int256 liqedCreditChange)
    {
        require(
            executor == liquidator || state.operatorRegistry[liquidator][executor], Errors.INVALID_LIQUIDATION_EXECUTOR
        );
        require(liquidatedTrader != liquidator, Errors.SELF_LIQUIDATION_NOT_ALLOWED);
        uint256 insuranceFee;
        (liqtorPaperChange, liqtorCreditChange, insuranceFee) =
            getLiquidateCreditAmount(state, perp, liquidatedTrader, requestPaperAmount);
        state.primaryCredit[state.insurance] += SafeCast.toInt256(insuranceFee);

        // liquidated trader balance change
        liqedCreditChange = liqtorCreditChange * -1 - SafeCast.toInt256(insuranceFee);
        liqedPaperChange = liqtorPaperChange * -1;

        // events
        uint256 ltSN = state.positionSerialNum[liquidatedTrader][perp];
        uint256 liquidatorSN = state.positionSerialNum[liquidator][perp];
        emit BeingLiquidated(perp, liquidatedTrader, liqedPaperChange, liqedCreditChange, ltSN);
        emit JoinLiquidation(perp, liquidator, liquidatedTrader, liqtorPaperChange, liqtorCreditChange, liquidatorSN);
        emit ChargeInsurance(perp, liquidatedTrader, insuranceFee);
    }

    function getMarkPrice(Types.State storage state, address perp) external view returns (uint256 price) {
        price = IPriceSource(state.perpRiskParams[perp].markPriceSource).getMarkPrice();
    }

    function handleBadDebt(Types.State storage state, address liquidatedTrader) external {
        if (state.openPositions[liquidatedTrader].length == 0 && !Liquidation._isMMSafe(state, liquidatedTrader)) {
            int256 primaryCredit = state.primaryCredit[liquidatedTrader];
            uint256 secondaryCredit = state.secondaryCredit[liquidatedTrader];
            state.primaryCredit[liquidatedTrader] = 0;
            state.secondaryCredit[liquidatedTrader] = 0;
            state.primaryCredit[state.insurance] += primaryCredit;
            state.secondaryCredit[state.insurance] += secondaryCredit;
            emit HandleBadDebt(liquidatedTrader, primaryCredit, secondaryCredit);
        }
    }
}
