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

    // if the order is long, filledPaperAmount>0 and filledCreditAmount<0
    // if sender charge fee from this order, fee>0
    // if sender provide rebate to this order, fee<0
    event OrderFilled(
        bytes32 indexed orderHash,
        address indexed trader,
        int256 filledPaperAmount,
        int256 filledCreditAmount,
        uint256 positionSerialNum
    );

    event RelayerFeeCollected(address indexed relayer, int256 fee);

    function _approveTrade(
        Types.State storage state,
        address orderSender,
        bytes calldata tradeData
    ) public returns (Types.MatchResult memory result) {
        result.perp = msg.sender;
        require(
            state.perpRiskParams[result.perp].isRegistered,
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

        // validate orders
        bytes32[] memory orderHashList = new bytes32[](orderList.length);
        for (uint256 i = 0; i < orderList.length; i++) {
            orderHashList[i] = _validateOrder(
                state.domainSeparator,
                orderList[i],
                signatureList[i]
            );
            require(orderList[i].perp == result.perp, Errors.PERP_MISMATCH);
            require(
                orderList[i].orderSender == orderSender ||
                    orderList[i].orderSender == address(0),
                Errors.INVALID_ORDER_SENDER
            );
            state.filledPaperAmount[orderHashList[i]] += matchPaperAmount[i];
            require(
                state.filledPaperAmount[orderHashList[i]] <=
                    orderList[i].paperAmount.abs(),
                Errors.ORDER_FILLED_OVERFLOW
            );
            _addPosition(state, result.perp, orderList[i].signer);
        }

        // de-duplicate trader to save gas
        // traderList[0] is taker
        {
            uint256 uniqueTraderNum = 1;
            uint256 totalMakerFilledPaper;

            for (uint256 i = 1; i < orderList.length; i++) {
                if (orderList[i].signer != orderList[i - 1].signer) {
                    uniqueTraderNum += 1;
                }
                totalMakerFilledPaper += matchPaperAmount[i];
            }
            require(
                matchPaperAmount[0] == totalMakerFilledPaper,
                Errors.TAKER_TRADE_AMOUNT_WRONG
            );
            require(uniqueTraderNum >= 2, Errors.INVALID_TRADER_NUMBER);
            result.traderList = new address[](uniqueTraderNum);
            result.traderList[0] = orderList[0].signer;
        }

        // validate maker order & merge paper amount
        result.paperChangeList = new int256[](result.traderList.length);
        result.creditChangeList = new int256[](result.traderList.length);
        {
            uint256 currentTraderIndex = 1;
            for (uint256 i = 1; i < orderList.length; i++) {
                _priceMatchCheck(orderList[0], orderList[i]);
                if (i > 1 && orderList[i].signer != orderList[i - 1].signer) {
                    currentTraderIndex += 1;
                    result.traderList[currentTraderIndex] = orderList[i].signer;
                }

                // matching result
                int256 paperChange = orderList[i].paperAmount > 0
                    ? int256(matchPaperAmount[i])
                    : -1 * int256(matchPaperAmount[i]);
                int256 creditChange = (paperChange *
                    orderList[i].creditAmount) / orderList[i].paperAmount;
                int256 fee = int256(creditChange.abs()).decimalMul(
                    orderList[i].makerFeeRate
                );
                uint256 serialNum = state.positionSerialNum[orderList[i].signer][result.perp];
                emit OrderFilled(
                    orderHashList[i],
                    orderList[i].signer,
                    paperChange,
                    creditChange - fee,
                    serialNum
                );
                result.paperChangeList[currentTraderIndex] += paperChange;
                result.creditChangeList[currentTraderIndex] += creditChange;
                result.creditChangeList[currentTraderIndex] -= fee;
                result.paperChangeList[0] -= paperChange;
                result.creditChangeList[0] -= creditChange;
                result.orderSenderFee += fee;
            }
        }

        // trading fee related
        {
            int256 takerFee = int256(result.creditChangeList[0].abs())
                .decimalMul(orderList[0].takerFeeRate);
            result.creditChangeList[0] -= takerFee;
            result.orderSenderFee += takerFee;
            state.trueCredit[orderSender] += result.orderSenderFee;
            if (result.orderSenderFee < 0) {
                require(
                    Liquidation._isSafe(state, orderSender),
                    Errors.ORDER_SENDER_NOT_SAFE
                );
            }
            emit RelayerFeeCollected(orderSender, result.orderSenderFee);
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
                    order.nounce
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
