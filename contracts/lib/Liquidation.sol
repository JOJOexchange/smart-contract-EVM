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
            uint256 strictLiqThreshold
        )
    {
        // sum net value and exposure among all markets
        for (uint256 i = 0; i < state.openPositions[trader].length; i++) {
            (int256 paperAmount, int256 credit) = IPerpetual(
                state.openPositions[trader][i]
            ).balanceOf(trader);
            Types.RiskParams memory params = state.perpRiskParams[
                state.openPositions[trader][i]
            ];
            int256 price = int256(IMarkPriceSource(params.markPriceSource)
                .getMarkPrice());

            netPositionValue += paperAmount.decimalMul(price) + credit;
            exposure += paperAmount.decimalMul(price).abs();

            // use the most strict liquidation requirement
            if (params.liquidationThreshold > strictLiqThreshold) {
                strictLiqThreshold = params.liquidationThreshold;
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
            uint256 exposure,
            uint256 strictLiqThreshold
        ) = getTotalExposure(state, trader);

        // net value >= exposure * liqThreshold
        return
            netPositionValue +
                state.primaryCredit[trader] +
                int256(state.secondaryCredit[trader]) >=
            int256((exposure * strictLiqThreshold) / 10**18);
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
            uint256 exposure,
            uint256 strictLiqThreshold
        ) = getTotalExposure(state, trader);
        return
            netPositionValue + state.primaryCredit[trader] >= 0 &&
            netPositionValue +
                state.primaryCredit[trader] +
                int256(state.secondaryCredit[trader]) >=
            int256((exposure * strictLiqThreshold) / 10**18);
    }

    /*
        Check if a certain position safe.
        Because we use cross mode, the safety of position also depends on
        positions in other markets.
        isPositionSafe use the liqThreshold of this position but not the 
        most strict liqThreshold.
    */
    function isPositionSafe(
        Types.State storage state,
        address trader,
        address perp
    ) public view returns (bool) {
        (int256 netPositionValue, uint256 exposure, ) = getTotalExposure(
            state,
            trader
        );
        uint256 liqThreshold = state.perpRiskParams[perp].liquidationThreshold;
        return
            netPositionValue +
                state.primaryCredit[trader] +
                int256(state.secondaryCredit[trader]) >=
            int256((exposure * liqThreshold) / 10**18);
    }

    function getLiquidationPrice(
        Types.State storage state,
        address trader,
        address perp
    ) external view returns (uint256 liquidationPrice) {
        (int256 paperAmount, ) = IPerpetual(perp).balanceOf(trader);
        if (paperAmount == 0) {
            return 0;
        }

        (int256 positionNetValue, uint256 exposure, ) = getTotalExposure(
            state,
            trader
        );

        Types.RiskParams memory params = state.perpRiskParams[perp];
        uint256 markPrice = IMarkPriceSource(params.markPriceSource)
            .getMarkPrice();

        // remove perp paper influence
        exposure -= paperAmount.decimalMul(int256(markPrice)).abs();
        int256 netValue = positionNetValue +
            state.primaryCredit[trader] +
            int256(state.secondaryCredit[trader]) -
            paperAmount.decimalMul(int256(markPrice));

        /*
            To avoid liquidation, we need:
            exposure * liquidationThreshold <= netValue

            The change of mark price will influence the value of this position's paper.
            So we first eliminate the impact of this paper value, then we have:
            exposure = exposure - abs(paperAmount) * price
            netValue = netValue - paperAmount * price
            
            Then we consider under what circumstances the equal sign holds.

            if paperAmount > 0
                (exposure + paperAmount * liqPrice) * liqThreshold = netValue + paperAmount * liqPrice
                exposure * liqThreshold - netValue = paperAmount * liqPrice * (1-liqThreshold)
                liqPrice = (exposure * liqThreshold - netValue) / paperAmount / (1-liqThreshold)
                    >> if paperAmount=0, no liqPrice
                    >> if the right side is less than zero, the account is super safe, no liqPrice

            if paperAmount < 0
                (exposure - paperAmount * liqPrice) * liqThreshold = netValue + paperAmount * liqPrice
                exposure * liqThreshold - netValue = paperAmount * liqPrice * (1+liqThreshold)
                liqPrice = (exposure * liqThreshold - netValue) / paperAmount / (1+liqThreshold)
                    >> if paperAmount=0, no liqPrice
                    >> if the right side is less than zero, the position must already be liquidated, no liqPrice

            let temp1 = exposure * liqThreshold - netValue
            let temp2 = 
                1-liqThreshold, if paperAmount > 0
                1+liqThreshold, if paperAmount < 0

            then we have:
                liqPrice = temp1/paperAmount/temp2
        */
        int256 temp1 = int256(
            (exposure * params.liquidationThreshold) / 10**18
        ) - netValue;
        int256 temp2 = int256(
            paperAmount > 0
                ? 10**18 - params.liquidationThreshold
                : 10**18 + params.liquidationThreshold
        );
        // If the paperAmount too small, liqPrice is meaningless, return 0
        if (temp2.decimalMul(paperAmount) == 0) {
            return 0;
        }
        int256 liqPrice = temp1.decimalDiv(temp2.decimalMul(paperAmount));
        if (liqPrice < 0) {
            return 0;
        } else {
            liquidationPrice = uint256(liqPrice);
        }
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
        require(
            !isPositionSafe(state, liquidatedTrader, perp),
            Errors.ACCOUNT_IS_SAFE
        );

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

    function handleBadDebt(Types.State storage state, address liquidatedTrader) external {
        require(
            !Liquidation._isSafe(state, liquidatedTrader),
            Errors.ACCOUNT_IS_SAFE
        );
        require(
            state.openPositions[liquidatedTrader].length == 0,
            Errors.TRADER_STILL_IN_LIQUIDATION
        );
        int256 primaryCredit = state.primaryCredit[liquidatedTrader];
        uint256 secondaryCredit = state.secondaryCredit[liquidatedTrader];
        state.primaryCredit[state.insurance] += primaryCredit;
        state.secondaryCredit[state.insurance] += secondaryCredit;
        state.primaryCredit[liquidatedTrader] = 0;
        state.secondaryCredit[liquidatedTrader] = 0;
        emit HandleBadDebt(liquidatedTrader, primaryCredit, secondaryCredit);
    }
}
