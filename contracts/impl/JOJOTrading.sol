/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "./JOJOFunding.sol";
import "../intf/IPerpetual.sol";
import "../utils/SignedDecimalMath.sol";
import "../utils/JOJOOrder.sol";
import "../utils/Errors.sol";

contract JOJOTrading is JOJOFunding {
    using SignedMath for int256;
    using Math for uint256;

    mapping(bytes32 => uint256) public filledPaperAmount;
    address public orderValidator;

    event OrderFilled(
        bytes32 orderHash,
        int256 filledPaperAmount,
        int256 filledCreditAmount,
        int256 fee
    );

    // charge fee from all makers and taker, then transfer the fee to orderSender
    // if the taker open long and maker open short, tradePaperAmount > 0
    // Pay attention to sorting when submitting, then de-duplicate here to save gas
    function approveTrade(address orderSender, bytes calldata tradeData)
        external
        nonReentrant
        returns (
            address taker,
            address[] memory makerList,
            int256[] memory tradePaperAmountList,
            int256[] memory tradeCreditAmountList
        )
    {
        require(
            perpRiskParams[msg.sender].markPriceSource != address(0),
            Errors.PERP_NOT_REGISTERED
        );
        // first taker and following multiple makers
        // orderList >= 2
        // matchPaperAmount.length = orderList.length
        // matchPaperAmount[0] = summary of the following
        (
            JOJOOrder.Order[] memory orderList,
            bytes[] memory signatureList,
            uint256[] memory matchPaperAmount
        ) = abi.decode(tradeData, (JOJOOrder.Order[], bytes[], uint256[]));

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
            makerList = new address[](uniqueMakerNum);
        }

        // validate maker order & merge paper amount
        tradePaperAmountList = new int256[](makerList.length);
        tradeCreditAmountList = new int256[](makerList.length);
        int256[] memory makerFeeList = new int256[](makerList.length);
        {
            uint256 currentMakerIndex;
            for (uint256 i = 1; i < orderList.length; i++) {
                bytes32 makerOrderHash = JOJOOrder(orderValidator)
                    .validateOrder(orderList[i], signatureList[i]);
                require(orderList[i].perp == msg.sender, Errors.PERP_MISMATCH);
                require(
                    orderList[i].orderSender == orderSender ||
                        orderList[i].orderSender == address(0),
                    Errors.INVALID_ORDER_SENDER
                );
                require(
                    filledPaperAmount[makerOrderHash] + matchPaperAmount[i] <=
                        orderList[i].paperAmount.abs(),
                    Errors.ORDER_FILLED_OVERFLOW
                );
                filledPaperAmount[makerOrderHash] += matchPaperAmount[i];

                _priceMatchCheck(orderList[0], orderList[i]);
                int256 paper = orderList[0].paperAmount > 0
                    ? int256(matchPaperAmount[i])
                    : -1 * int256(matchPaperAmount[i]);

                // welcome new maker
                _addPosition(msg.sender, orderList[i].signer);
                if (i > 1 && orderList[i].signer != orderList[i - 1].signer) {
                    currentMakerIndex += 1;
                }

                tradePaperAmountList[currentMakerIndex] += paper;
                tradeCreditAmountList[currentMakerIndex] +=
                    (paper * orderList[i].creditAmount) /
                    orderList[i].paperAmount;
                makerFeeList[currentMakerIndex] +=
                    int256(matchPaperAmount[i]) *
                    orderList[i].makerFeeRate;
            }
        }

        // modify taker order status
        {
            taker = orderList[0].signer;
            bytes32 takerOrderHash = JOJOOrder(orderValidator).validateOrder(
                orderList[0],
                signatureList[0]
            );
            require(orderList[0].perp == msg.sender, Errors.PERP_MISMATCH);
            require(
                orderList[0].orderSender == orderSender ||
                    orderList[0].orderSender == address(0),
                Errors.INVALID_ORDER_SENDER
            );
            require(
                filledPaperAmount[takerOrderHash] + matchPaperAmount[0] <=
                    orderList[0].paperAmount.abs(),
                Errors.ORDER_FILLED_OVERFLOW
            );
            filledPaperAmount[takerOrderHash] += matchPaperAmount[0];
            _addPosition(msg.sender, taker);
        }

        // trading fee related

        int256 orderSenderFee;
        int256 takerFee = int256(matchPaperAmount[0]) *
            int256(orderList[0].takerFeeRate);
        if (takerFee != 0) {
            IPerpetual(msg.sender).changeCredit(taker, takerFee);
            orderSenderFee -= takerFee;
        }

        for (uint256 i = 0; i < makerList.length; i++) {
            if (makerFeeList[i] != 0) {
                IPerpetual(msg.sender).changeCredit(
                    makerList[i],
                    makerFeeList[i]
                );
                orderSenderFee -= makerFeeList[i];
            }
        }

        if (orderSenderFee != 0) {
            IPerpetual(msg.sender).changeCredit(orderSender, orderSenderFee);
            if (orderSenderFee < 0) {
                isSafe(orderSender);
            }
        }
    }

    function _priceMatchCheck(
        JOJOOrder.Order memory takerOrder,
        JOJOOrder.Order memory makerOrder
    ) internal pure {
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
}
