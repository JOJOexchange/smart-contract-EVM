/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../intf/IPerpetual.sol";
import "../intf/ITradingProxy.sol";
import "../utils/SignedDecimalMath.sol";
import "../utils/Errors.sol";
import "./Liquidation.sol";
import "./EIP712.sol";
import "./Types.sol";

library Trading {
    using SignedDecimalMath for int256;
    using Math for uint256;

    event OrderFilled(
        bytes32 orderHash,
        int256 filledPaperAmount,
        int256 filledCreditAmount,
        int256 fee
    );

    // charge fee from all makers and taker, then transfer the fee to orderSender
    // if the taker open long and maker open short, tradePaperAmount > 0
    // Pay attention to sorting when submitting, then de-duplicate here to save gas
    function _approveTrade(
        Types.State storage state,
        address orderSender,
        bytes calldata tradeData
    ) public returns (Types.MatchResult memory result) {
        require(
            state.perpRiskParams[msg.sender].isRegistered,
            Errors.PERP_NOT_REGISTERED
        );
        // first taker and following multiple makers
        // orderList >= 2
        // matchPaperAmount.length = orderList.length
        // matchPaperAmount[0] = summary of the following
        (
            Types.Order[] memory orderList,
            bytes[] memory signatureList,
            uint256[] memory matchPaperAmount
        ) = abi.decode(tradeData, (Types.Order[], bytes[], uint256[]));

        // de-duplicate maker to save gas
        {
            uint256 uniqueMakerNum = 1;
            uint256 totalMakerFilledPaper = matchPaperAmount[1];
            for (uint256 i = 2; i < orderList.length; i++) {
                if (orderList[i].signer != orderList[i - 1].signer) {
                    uniqueMakerNum += 1;
                }
                totalMakerFilledPaper += matchPaperAmount[i];
            }
            require(
                matchPaperAmount[0] == totalMakerFilledPaper,
                Errors.TAKER_TRADE_AMOUNT_WRONG
            );
            result.makerList = new address[](uniqueMakerNum);
            result.makerList[0] = orderList[1].signer;
        }

        // validate maker order & merge paper amount
        result.tradePaperAmountList = new int256[](result.makerList.length);
        result.tradeCreditAmountList = new int256[](result.makerList.length);
        result.makerFeeList = new int256[](result.makerList.length);
        {
            uint256 currentMakerIndex;
            for (uint256 i = 1; i < orderList.length; i++) {
                bytes32 makerOrderHash = _validateOrder(
                    state.domainSeparator,
                    orderList[i],
                    signatureList[i]
                );
                require(orderList[i].perp == msg.sender, Errors.PERP_MISMATCH);
                require(
                    orderList[i].orderSender == orderSender ||
                        orderList[i].orderSender == address(0),
                    Errors.INVALID_ORDER_SENDER
                );
                state.filledPaperAmount[makerOrderHash] += matchPaperAmount[i];
                require(
                    state.filledPaperAmount[makerOrderHash] <=
                        orderList[i].paperAmount.abs(),
                    Errors.ORDER_FILLED_OVERFLOW
                );

                _priceMatchCheck(orderList[0], orderList[i]);
                int256 paper = orderList[0].paperAmount > 0
                    ? int256(matchPaperAmount[i])
                    : -1 * int256(matchPaperAmount[i]);

                // welcome new maker
                _addPosition(state, msg.sender, orderList[i].signer);
                if (i > 1 && orderList[i].signer != orderList[i - 1].signer) {
                    currentMakerIndex += 1;
                    result.makerList[currentMakerIndex] = orderList[i].signer;
                }

                // matching result
                int256 matchCreditAmount = (paper * orderList[i].creditAmount) /
                    orderList[i].paperAmount;
                result.tradePaperAmountList[currentMakerIndex] += paper;
                result.tradeCreditAmountList[
                    currentMakerIndex
                ] += matchCreditAmount;

                // fees
                result.makerFeeList[currentMakerIndex] += int256(
                    matchCreditAmount.abs()
                ).decimalMul(orderList[i].makerFeeRate);
                result.takerFee += int256(matchCreditAmount.abs()).decimalMul(
                    orderList[0].takerFeeRate
                );
            }
        }

        // modify taker order status
        {
            result.taker = orderList[0].signer;
            bytes32 takerOrderHash = _validateOrder(
                state.domainSeparator,
                orderList[0],
                signatureList[0]
            );
            require(orderList[0].perp == msg.sender, Errors.PERP_MISMATCH);
            require(
                orderList[0].orderSender == orderSender ||
                    orderList[0].orderSender == address(0),
                Errors.INVALID_ORDER_SENDER
            );
            state.filledPaperAmount[takerOrderHash] += matchPaperAmount[0];
            require(
                state.filledPaperAmount[takerOrderHash] <=
                    orderList[0].paperAmount.abs(),
                Errors.ORDER_FILLED_OVERFLOW
            );

            _addPosition(state, msg.sender, result.taker);
        }

        // trading fee related

        int256 orderSenderFee;
        if (result.takerFee != 0) {
            IPerpetual(msg.sender).changeCredit(
                result.taker,
                -1 * result.takerFee
            );
            orderSenderFee += result.takerFee;
        }

        for (uint256 i = 0; i < result.makerList.length; i++) {
            if (result.makerFeeList[i] != 0) {
                IPerpetual(msg.sender).changeCredit(
                    result.makerList[i],
                    -1 * result.makerFeeList[i]
                );
                orderSenderFee += result.makerFeeList[i];
            }
        }

        if (orderSenderFee != 0) {
            IPerpetual(msg.sender).changeCredit(orderSender, orderSenderFee);
            if (orderSenderFee < 0) {
                Liquidation._isSafe(state, orderSender);
            }
        }
    }

    function _priceMatchCheck(
        Types.Order memory takerOrder,
        Types.Order memory makerOrder
    ) private pure {
        require(takerOrder.perp == makerOrder.perp, Errors.PERP_MISMATCH);
        // require
        // takercredit * abs(makerpaper) / abs(takerpaper) + makercredit <= 0
        // makercredit - takercredit * makerpaper / takerpaper <= 0
        // if takerPaper > 0
        // makercredit * takerpaper <= takercredit * makerpaper
        // if takerPaper < 0
        // makercredit * takerpaper >= takercredit * makerpaper
        if (takerOrder.paperAmount > 0) {
            // taker open long, tradePaperAmount > 0
            require(makerOrder.paperAmount < 0, Errors.ORDER_PRICE_NOT_MATCH);
            require(
                makerOrder.creditAmount * takerOrder.paperAmount <=
                    takerOrder.creditAmount * makerOrder.paperAmount,
                Errors.ORDER_PRICE_NOT_MATCH
            );
        } else {
            // taker open short, tradePaperAmount < 0
            require(makerOrder.paperAmount > 0, Errors.ORDER_PRICE_NOT_MATCH);
            require(
                makerOrder.creditAmount * takerOrder.paperAmount >=
                    takerOrder.creditAmount * makerOrder.paperAmount,
                Errors.ORDER_PRICE_NOT_MATCH
            );
        }
    }

    function _addPosition(
        Types.State storage state,
        address perp,
        address trader
    ) private {
        if (!state.hasPosition[trader][perp]) {
            state.hasPosition[trader][perp] = true;
            state.openPositions[trader].push(perp);
        }
    }

    function _validateOrder(
        bytes32 domainSeparator,
        Types.Order memory order,
        bytes memory signature
    ) public returns (bytes32 orderHash) {
        orderHash = EIP712._hashTypedDataV4(
            domainSeparator,
            keccak256(
                abi.encode(
                    Types.ORDER_TYPEHASH,
                    order.perp,
                    order.paperAmount,
                    order.creditAmount,
                    order.makerFeeRate,
                    order.takerFeeRate,
                    order.signer,
                    order.orderSender,
                    order.expiration,
                    order.salt
                )
            )
        );
        if (Address.isContract(order.signer)) {
            require(
                ITradingProxy(order.signer).isValidPerpetualOperator(
                    ECDSA.recover(orderHash, signature)
                ),
                Errors.INVALID_ORDER_SIGNATURE
            );
        } else {
            require(
                ECDSA.recover(orderHash, signature) == order.signer,
                Errors.INVALID_ORDER_SIGNATURE
            );
        }
        require(
            (order.paperAmount < 0 && order.creditAmount > 0) ||
                (order.paperAmount > 0 && order.creditAmount < 0),
            Errors.ORDER_PRICE_NEGATIVE
        );
    }
}
