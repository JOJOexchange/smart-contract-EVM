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

    function _getTotalExposure(Types.State storage state, address trader)
        public
        returns (
            int256 netValue,
            uint256 exposure,
            uint256 liquidationThreshold
        )
    {
        int256 netValueDelta;
        uint256 exposureDelta;
        uint256 threshold;
        for (uint256 i = 0; i < [trader].length; i++) {
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

            // no position in this case
            if (exposureDelta == 0) {
                _removePosition(state, trader, i);
                // clear remaining credit if needed
                // if netValueDelta < 0, deposit credit to perp
                // if netValueDelta > 0, withdraw credit from perp
                if (netValueDelta != 0) {
                    IPerpetual(state.openPositions[trader][i]).changeCredit(
                        trader,
                        -1 * netValueDelta
                    );
                    state.trueCredit[trader] += netValueDelta;
                }
            }

            netValue += netValueDelta;
            exposure += exposureDelta;
            if (threshold > liquidationThreshold) {
                liquidationThreshold = threshold;
            }
        }
    }

    function _isSafe(Types.State storage state, address trader)
        public
        returns (bool)
    {
        if (state.openPositions[trader].length == 0) {
            return true;
        }
        (
            int256 netValue,
            uint256 exposure,
            uint256 liquidationThreshold
        ) = _getTotalExposure(state, trader);
        netValue =
            netValue +
            state.trueCredit[trader] +
            int256(state.virtualCredit[trader]);
        return netValue >= int256((exposure * liquidationThreshold) / 10**18);
    }

    // if the brokenTrader in long position, liquidatePaperAmount < 0 and liquidateCreditAmount > 0;
    function _getLiquidateCreditAmount(
        Types.State storage state,
        address brokenTrader,
        int256 liquidatePaperAmount
    ) external returns (int256 paperAmount, int256 creditAmount) {
        require(!_isSafe(state, brokenTrader), Errors.ACCOUNT_IS_SAFE);

        // get price
        Types.RiskParams memory params = state.perpRiskParams[msg.sender];
        require(params.isRegistered, Errors.PERP_NOT_REGISTERED);
        uint256 price = IMarkPriceSource(params.markPriceSource).getMarkPrice();
        uint256 priceOffset = (price * params.liquidationPriceOff) / 10**18;

        // calculate trade
        (int256 brokenPaperAmount, ) = IPerpetual(msg.sender).balanceOf(
            brokenTrader
        );
        require(brokenPaperAmount != 0, Errors.TRADER_HAS_NO_POSITION);
        // if (
        //     (brokenPaperAmount.abs() * price) / 10**18 >=
        //     params.largePositionThreshold
        // ) {
        //     brokenPaperAmount = int256(params.largePositionThreshold / 2);
        // }

        if (brokenPaperAmount > 0) {
            // close long
            price = price - priceOffset;
            paperAmount = brokenPaperAmount > liquidatePaperAmount
                ? liquidatePaperAmount
                : brokenPaperAmount;
        } else {
            // close short
            price = price + priceOffset;
            paperAmount = brokenPaperAmount < liquidatePaperAmount
                ? liquidatePaperAmount
                : brokenPaperAmount;
        }
        creditAmount = paperAmount.decimalMul(int256(price));

        // charge insurance fee
        uint256 insuranceFee = (creditAmount.abs() * params.insuranceFeeRate) /
            10**18;
        IPerpetual(msg.sender).changeCredit(
            brokenTrader,
            -1 * int256(insuranceFee)
        );
        IPerpetual(msg.sender).changeCredit(
            state.insurance,
            int256(insuranceFee)
        );
    }

    function _removePosition(
        Types.State storage state,
        address trader,
        uint256 index
    ) private {
        address[] storage positionList = state.openPositions[trader];
        state.hasPosition[trader][positionList[index]] = false;
        positionList[index] = positionList[positionList.length - 1];
        positionList.pop();
    }
}
