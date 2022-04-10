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

// import "hardhat/console.sol";

library Liquidation {
    using SignedDecimalMath for int256;

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

    event InsuranceChange(
        address indexed perp,
        address indexed liquidatedTrader,
        int256 creditChange
    );

    // For reference only
    // has accuracy problems, usually less than 10 wei
    // return 0 if can not calculate liquidation price
    function _getLiquidationPrice(
        Types.State storage state,
        address trader,
        address perp
    ) public view returns (uint256 liquidationPrice) {
        (int256 paperAmount, ) = IPerpetual(perp).balanceOf(trader);
        if (paperAmount == 0) {
            return 0;
        }

        (int256 positionNetValue, uint256 exposure, ) = _getTotalExposure(
            state,
            trader
        );

        Types.RiskParams memory params = state.perpRiskParams[perp];
        uint256 markPrice = IMarkPriceSource(params.markPriceSource)
            .getMarkPrice();

        // remove perp paper influence
        exposure -= (paperAmount.abs() * markPrice) / 10**18;
        int256 netValue = positionNetValue +
            state.trueCredit[trader] +
            int256(state.virtualCredit[trader]) -
            paperAmount.decimalMul(int256(markPrice));
        // console.logInt(positionNetValue);
        // console.log(exposure);
        // console.logInt(netValue);

        /*
            exposure * liquidationThreshold <= netValue

            if paperAmount > 0
            (exposure + paperAmount * price) * liqThreshold <= netValue + paperAmount * price
            exposure * liqThreshold - netValue <= paperAmount * price * (1-liqThreshold)
            price >= (exposure * liqThreshold - netValue) / paperAmount / (1-liqThreshold)
                >> if paperAmount=0, no liqPrice
                >> if the right side is less than zero, the account is super safe, no liqPrice

            if paperAmount < 0
            (exposure - paperAmount * price) * liqThreshold <= netValue + paperAmount * price
            exposure * liqThreshold - netValue <= paperAmount * price * (1+liqThreshold)
            price <= (exposure * liqThreshold - netValue) / paperAmount / (1+liqThreshold)
                >> if paperAmount=0, no liqPrice
                >> if the right side is less than zero, the position must already be liquidated, no liqPrice

            let temp1 = exposure * liqThreshold - netValue
            let temp2 = 1-liqThreshold or 1+liqThreshold
            then liqPrice = temp1/paperAmount/temp2
        */
        int256 temp1 = int256(
            (exposure * params.liquidationThreshold) / 10**18
        ) - netValue;
        // console.logInt(temp1);
        int256 temp2 = int256(
            paperAmount > 0
                ? 10**18 - params.liquidationThreshold
                : 10**18 + params.liquidationThreshold
        );
        // console.logInt(temp2);
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

    function _getTotalExposure(Types.State storage state, address trader)
        public
        view
        returns (
            int256 netPositionValue,
            uint256 exposure,
            uint256 strictLiqThreshold
        )
    {
        int256 netValueDelta;
        uint256 exposureDelta;
        uint256 threshold;
        for (uint256 i = 0; i < state.openPositions[trader].length; i++) {
            (int256 paperAmount, int256 credit) = IPerpetual(
                state.openPositions[trader][i]
            ).balanceOf(trader);
            Types.RiskParams memory params = state.perpRiskParams[
                state.openPositions[trader][i]
            ];
            uint256 price = IMarkPriceSource(params.markPriceSource)
                .getMarkPrice();
            int256 signedExposure = paperAmount.decimalMul(int256(price));

            netValueDelta = signedExposure + credit;
            exposureDelta = signedExposure.abs();
            threshold = params.liquidationThreshold;

            netPositionValue += netValueDelta;
            exposure += exposureDelta;
            if (threshold > strictLiqThreshold) {
                strictLiqThreshold = threshold;
            }
        }
    }

    // don't count virtual credit
    // check overall safe
    function _isSolidSafe(Types.State storage state, address trader)
        public
        view
        returns (bool)
    {
        (
            int256 netPositionValue,
            uint256 exposure,
            uint256 strictLiqThreshold
        ) = _getTotalExposure(state, trader);
        return
            netPositionValue + state.trueCredit[trader] >=
            int256((exposure * strictLiqThreshold) / 10**18);
    }

    // check overall safe
    function _isSafe(Types.State storage state, address trader)
        public
        view
        returns (bool)
    {
        (
            int256 netPositionValue,
            uint256 exposure,
            uint256 strictLiqThreshold
        ) = _getTotalExposure(state, trader);

        return
            netPositionValue +
                state.trueCredit[trader] +
                int256(state.virtualCredit[trader]) >=
            int256((exposure * strictLiqThreshold) / 10**18);
    }

    // check if a single position safe
    function _isPositionSafe(
        Types.State storage state,
        address trader,
        address perp
    ) public view returns (bool) {
        (int256 netPositionValue, uint256 exposure, ) = _getTotalExposure(
            state,
            trader
        );
        uint256 liqThreshold = state.perpRiskParams[perp].liquidationThreshold;
        return
            netPositionValue +
                state.trueCredit[trader] +
                int256(state.virtualCredit[trader]) >=
            int256((exposure * liqThreshold) / 10**18);
    }

    function _getLiquidateCreditAmount(
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
        require(
            !_isPositionSafe(state, liquidatedTrader, perp),
            Errors.ACCOUNT_IS_SAFE
        );

        // calculate paper change
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
        Types.RiskParams memory params = state.perpRiskParams[perp];
        require(params.isRegistered, Errors.PERP_NOT_REGISTERED);
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

    function _positionClear(Types.State storage state, address trader)
        external
    {
        Types.RiskParams memory params = state.perpRiskParams[msg.sender];
        require(params.isRegistered, Errors.PERP_NOT_REGISTERED);

        (, int256 creditAmount) = IPerpetual(msg.sender).balanceOf(trader);
        IPerpetual(msg.sender).changeCredit(trader, -1 * creditAmount);
        state.trueCredit[trader] += creditAmount;
        state.positionSerialNum[trader][msg.sender] += 1;

        state.hasPosition[trader][msg.sender] = false;
        address[] storage positionList = state.openPositions[trader];
        for (uint256 i = 0; i < positionList.length; i++) {
            if (positionList[i] == msg.sender) {
                positionList[i] = positionList[positionList.length - 1];
                positionList.pop();
                break;
            }
        }
    }
}
