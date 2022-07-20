/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "../intf/IPerpetual.sol";
import "../intf/IMarkPriceSource.sol";
import "../utils/SignedDecimalMath.sol";
import "../utils/Errors.sol";
import "./Types.sol";

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
    event InsuranceChange(
        address indexed perp,
        address indexed liquidatedTrader,
        int256 creditChange
    );

    event HandleBadDebt(
        address indexed liquidatedTrader,
        int256 primaryCredit,
        uint256 secondaryCredit
    );

    // ========== trader safety check ==========

    function getTotalExposure(Types.State storage state, address trader)
        public
        view
        returns (
            int256 netPositionValue,
            uint256 exposure,
            uint256 maintenanceMargin
        )
    {
        // sum net value and exposure among all markets
        for (uint256 i = 0; i < state.openPositions[trader].length; ) {
            (int256 paperAmount, int256 creditAmount) = IPerpetual(
                state.openPositions[trader][i]
            ).balanceOf(trader);
            Types.RiskParams memory params = state.perpRiskParams[
                state.openPositions[trader][i]
            ];
            int256 price = int256(
                IMarkPriceSource(params.markPriceSource).getMarkPrice()
            );

            netPositionValue += paperAmount.decimalMul(price) + creditAmount;
            uint256 exposureIncrement = paperAmount.decimalMul(price).abs();
            exposure += exposureIncrement;
            maintenanceMargin +=
                (exposureIncrement * params.liquidationThreshold) /
                10**18;

            unchecked {
                ++i;
            }
        }
    }

    // check overall safety
    function _isSafe(Types.State storage state, address trader)
        internal
        view
        returns (bool)
    {
        (
            int256 netPositionValue,
            ,
            uint256 maintenanceMargin
        ) = getTotalExposure(state, trader);

        // net value >= maintenanceMargin
        return
            netPositionValue +
                state.primaryCredit[trader] +
                int256(state.secondaryCredit[trader]) >=
            int256(maintenanceMargin);
    }

    /*
        More strict than _isSafe.
        Additional requirement: netPositionValue + primaryCredit >= 0
        used when traders transfer out primary credit.
    */
    function _isSolidSafe(Types.State storage state, address trader)
        internal
        view
        returns (bool)
    {
        (
            int256 netPositionValue,
            ,
            uint256 maintenanceMargin
        ) = getTotalExposure(state, trader);
        return
            netPositionValue + state.primaryCredit[trader] >= 0 &&
            netPositionValue +
                state.primaryCredit[trader] +
                int256(state.secondaryCredit[trader]) >=
            int256(maintenanceMargin);
    }

    /// @return liquidationPrice It should be considered as absolutely
    /// safe or being liquidated if return 0.
    function getLiquidationPrice(
        Types.State storage state,
        address trader,
        address perp
    ) external view returns (uint256 liquidationPrice) {
        if (!state.hasPosition[trader][perp]) {
            return 0;
        }

        /*
            To avoid liquidation, we need:
            netValue >= maintenanceMargin

            We first calculate the maintenanceMargin for all other markets' positions.
            Let's call it maintenanceMargin'

            Then we have netValue of the account.
            Let's call it netValue'

            So we have:
            netValue' + paperAmount * price + creditAmount >= maintenanceMargin' + abs(paperAmount) * price * liquidationThreshold
            
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
            
            If liqPrice<0, it should be considered as absolutely safe or being liquidated. 
        */
        int256 maintenanceMarginPrime;
        int256 netValuePrime = state.primaryCredit[trader] +
            int256(state.secondaryCredit[trader]);
        for (uint256 i = 0; i < state.openPositions[trader].length; i++) {
            address p = state.openPositions[trader][i];
            if (perp != p) {
                (
                    int256 paperAmountPrime,
                    int256 creditAmountPrime
                ) = IPerpetual(p).balanceOf(trader);
                Types.RiskParams memory params = state.perpRiskParams[p];
                int256 price = int256(
                    IMarkPriceSource(params.markPriceSource).getMarkPrice()
                );
                netValuePrime +=
                    paperAmountPrime.decimalMul(price) +
                    creditAmountPrime;
                maintenanceMarginPrime += int256(
                    (paperAmountPrime.decimalMul(price).abs() *
                        params.liquidationThreshold) / 10**18
                );
            }
        }
        (int256 paperAmount, int256 creditAmount) = IPerpetual(perp).balanceOf(
            trader
        );
        int256 multiplier = paperAmount > 0
            ? int256(10**18 - state.perpRiskParams[perp].liquidationThreshold)
            : int256(10**18 + state.perpRiskParams[perp].liquidationThreshold);
        int256 liqPrice = (maintenanceMarginPrime -
            netValuePrime -
            creditAmount).decimalDiv(paperAmount).decimalDiv(multiplier);
        return liqPrice < 0 ? 0 : uint256(liqPrice);
    }

    /*
        Using a fixed discount price model.
        Will help you liquidate up to the position size.
    */
    function getLiquidateCreditAmount(
        Types.State storage state,
        address perp,
        address liquidatedTrader,
        int256 requestPaperAmount
    )
        external
        view
        returns (
            int256 liqtorPaperChange,
            int256 liqtorCreditChange,
            uint256 insuranceFee
        )
    {
        // only registered perp
        Types.RiskParams memory params = state.perpRiskParams[perp];
        require(params.isRegistered, Errors.PERP_NOT_REGISTERED);

        // can not liquidate a safe trader
        require(!_isSafe(state, liquidatedTrader), Errors.ACCOUNT_IS_SAFE);

        // calculate paper change, up to the position size
        (int256 brokenPaperAmount, ) = IPerpetual(perp).balanceOf(
            liquidatedTrader
        );
        require(brokenPaperAmount != 0, Errors.TRADER_HAS_NO_POSITION);
        require(
            requestPaperAmount * brokenPaperAmount >= 0,
            Errors.LIQUIDATION_REQUEST_AMOUNT_WRONG
        );
        liqtorPaperChange = requestPaperAmount.abs() > brokenPaperAmount.abs()
            ? brokenPaperAmount
            : requestPaperAmount;

        // get price
        uint256 price = IMarkPriceSource(params.markPriceSource).getMarkPrice();
        uint256 priceOffset = (price * params.liquidationPriceOff) / 10**18;
        price = liqtorPaperChange > 0
            ? price - priceOffset
            : price + priceOffset;

        // calculate credit change
        liqtorCreditChange = -1 * liqtorPaperChange.decimalMul(int256(price));
        insuranceFee =
            (liqtorCreditChange.abs() * params.insuranceFeeRate) /
            10**18;
    }

    function getMarkPrice(Types.State storage state, address perp)
        external
        view
        returns (uint256 price)
    {
        price = IMarkPriceSource(state.perpRiskParams[perp].markPriceSource)
            .getMarkPrice();
    }

    function handleBadDebt(Types.State storage state, address liquidatedTrader)
        external
    {
        if (
            state.openPositions[liquidatedTrader].length == 0 &&
            !Liquidation._isSafe(state, liquidatedTrader)
        ) {
            int256 primaryCredit = state.primaryCredit[liquidatedTrader];
            uint256 secondaryCredit = state.secondaryCredit[liquidatedTrader];
            state.primaryCredit[state.insurance] += primaryCredit;
            state.secondaryCredit[state.insurance] += secondaryCredit;
            state.primaryCredit[liquidatedTrader] = 0;
            state.secondaryCredit[liquidatedTrader] = 0;
            emit HandleBadDebt(
                liquidatedTrader,
                primaryCredit,
                secondaryCredit
            );
        }
    }
}
