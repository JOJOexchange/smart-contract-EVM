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

    event PositionClear(
        address indexed user,
        address indexed perp,
        uint256 serialId
    );

    function _getTotalExposure(Types.State storage state, address trader)
        public
        view
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

            netValue += netValueDelta;
            exposure += exposureDelta;
            if (threshold > liquidationThreshold) {
                liquidationThreshold = threshold;
            }
        }
    }

    function _isSafe(Types.State storage state, address trader)
        public
        view
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

    function _getLiquidateCreditAmount(
        Types.State storage state,
        address liquidatedTrader,
        uint256 requestPaperAmount
    )
        external
        view
        returns (
            int256 ltPaperChange,
            int256 ltCreditChange,
            uint256 insuranceFee
        )
    {
        require(!_isSafe(state, liquidatedTrader), Errors.ACCOUNT_IS_SAFE);

        // get price
        Types.RiskParams memory params = state.perpRiskParams[msg.sender];
        require(params.isRegistered, Errors.PERP_NOT_REGISTERED);
        uint256 price = IMarkPriceSource(params.markPriceSource).getMarkPrice();
        uint256 priceOffset = (price * params.liquidationPriceOff) / 10**18;

        // calculate trade
        (int256 brokenPaperAmount, ) = IPerpetual(msg.sender).balanceOf(
            liquidatedTrader
        );
        require(brokenPaperAmount != 0, Errors.TRADER_HAS_NO_POSITION);

        if (brokenPaperAmount > 0) {
            // close long
            price = price - priceOffset;
            ltPaperChange = brokenPaperAmount.abs() > requestPaperAmount
                ? -1*int256(requestPaperAmount)
                : -1 * brokenPaperAmount;
        } else {
            // close short
            price = price + priceOffset;
            ltPaperChange = brokenPaperAmount.abs() > requestPaperAmount
                ? int256(requestPaperAmount)
                : -1 * brokenPaperAmount;
        }
        ltCreditChange = ltPaperChange.decimalMul(int256(price));
        insuranceFee = (ltCreditChange.abs() * params.insuranceFeeRate) / 10**18;
    }

    function _positionClear(Types.State storage state, address trader)
        external
    {
        Types.RiskParams memory params = state.perpRiskParams[msg.sender];
        require(params.isRegistered, Errors.PERP_NOT_REGISTERED);

        (, int256 creditAmount) = IPerpetual(msg.sender).balanceOf(trader);
        IPerpetual(msg.sender).changeCredit(trader, -1 * creditAmount);
        emit PositionClear(
            trader,
            msg.sender,
            state.positionSerialId[trader][msg.sender]
        );
        state.positionSerialId[trader][msg.sender] += 1;

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
