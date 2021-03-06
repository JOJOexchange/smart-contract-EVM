/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "../intf/IPerpetual.sol";
import "../intf/IMarkPriceSource.sol";
import "../utils/SignedDecimalMath.sol";
import "../utils/Errors.sol";
import "./EIP712.sol";
import "./Types.sol";
import "./Liquidation.sol";

library Trading {
    using SignedDecimalMath for int256;
    using Math for uint256;

    // ========== events ==========

    /*
        orderFilledPaperAmount>0 and filledCreditAmount<0 if the order open long,
        and vice versa.
        filledCreditAmount including fees.
    */
    event OrderFilled(
        bytes32 indexed orderHash,
        address indexed trader,
        address indexed perp,
        int256 orderFilledPaperAmount,
        int256 filledCreditAmount,
        uint256 positionSerialNum
    );

    // ========== matching[important] ==========

    /// @notice parse tradeData and calculate balance changes for perpetual.sol
    /// @dev can only be called by perpetual.sol. Every mathcing contains 1 taker
    /// and at least 1 maker.
    function _approveTrade(
        Types.State storage state,
        address orderSender,
        bytes calldata tradeData
    ) internal returns (Types.MatchResult memory result) {
        result.perp = msg.sender;
        require(
            state.perpRiskParams[result.perp].isRegistered,
            Errors.PERP_NOT_REGISTERED
        );
        require(
            state.validOrderSender[orderSender],
            Errors.INVALID_ORDER_SENDER
        );

        /*
            parse tradeData
            Pass in all orders and their signatures that need to be matched.
            Also, pass in the amount you want to fill each order.
        */
        (
            Types.Order[] memory orderList,
            bytes[] memory signatureList,
            uint256[] memory matchPaperAmount
        ) = abi.decode(tradeData, (Types.Order[], bytes[], uint256[]));

        // validate orders
        bytes32[] memory orderHashList = new bytes32[](orderList.length);
        for (uint256 i = 0; i < orderList.length; ) {
            Types.Order memory order = orderList[i];
            bytes32 orderHash = EIP712._hashTypedDataV4(
                state.domainSeparator,
                _structHash(order)
            );
            address recoverSigner = ECDSA.recover(orderHash, signatureList[i]);
            // requirements
            require(
                recoverSigner == order.signer ||
                    state.operatorRegistry[order.signer][recoverSigner],
                Errors.INVALID_ORDER_SIGNATURE
            );
            require(
                _info2Expiration(order.info) >= block.timestamp,
                Errors.ORDER_EXPIRED
            );
            require(
                (order.paperAmount < 0 && order.creditAmount > 0) ||
                    (order.paperAmount > 0 && order.creditAmount < 0),
                Errors.ORDER_PRICE_NEGATIVE
            );
            require(order.perp == result.perp, Errors.PERP_MISMATCH);
            require(
                i == 0 || order.signer != orderList[0].signer,
                Errors.ORDER_SELF_MATCH
            );
            state.orderFilledPaperAmount[orderHash] += matchPaperAmount[i];
            require(
                state.orderFilledPaperAmount[orderHash] <=
                    int256(orderList[i].paperAmount).abs(),
                Errors.ORDER_FILLED_OVERFLOW
            );
            // register position for quick query
            _addPosition(state, result.perp, orderList[i].signer);
            orderHashList[i] = orderHash;
            unchecked {
                ++i;
            }
        }

        /*
            traderList[0] is taker
            traderList[1:] are makers
            If a maker has more than one order, maker orders should be listed 
            in ascending order. So that the function could merge orders to save
            gas(by reducing balances chagne operations).
        */
        {
            require(orderList.length >= 2, Errors.INVALID_TRADER_NUMBER);
            // de-duplicated maker
            uint256 uniqueTraderNum = 2;
            uint256 totalMakerFilledPaper = matchPaperAmount[1];
            // start from the second maker, which is the third trader
            for (uint256 i = 2; i < orderList.length; i++) {
                totalMakerFilledPaper += matchPaperAmount[i];
                if (orderList[i].signer > orderList[i - 1].signer) {
                    uniqueTraderNum += 1;
                } else {
                    require(
                        orderList[i].signer == orderList[i - 1].signer,
                        Errors.ORDER_WRONG_SORTING
                    );
                }
            }
            // taker match amount must equals summary of makers' match amount
            require(
                matchPaperAmount[0] == totalMakerFilledPaper,
                Errors.TAKER_TRADE_AMOUNT_WRONG
            );
            result.traderList = new address[](uniqueTraderNum);
            // traderList[0] is taker
            result.traderList[0] = orderList[0].signer;
        }

        // merge maker orders
        result.paperChangeList = new int256[](result.traderList.length);
        result.creditChangeList = new int256[](result.traderList.length);
        {
            // the taker's trader index is 0
            // the first maker's trader index is 1
            uint256 currentTraderIndex = 1;
            result.traderList[1] = orderList[1].signer;
            for (uint256 i = 1; i < orderList.length; ) {
                _priceMatchCheck(orderList[0], orderList[i]);

                // new maker, currentTraderIndex +1
                if (i >= 2 && orderList[i].signer != orderList[i - 1].signer) {
                    currentTraderIndex += 1;
                    result.traderList[currentTraderIndex] = orderList[i].signer;
                }

                // calculate matching result, use maker's price
                int256 paperChange = orderList[i].paperAmount > 0
                    ? int256(matchPaperAmount[i])
                    : -1 * int256(matchPaperAmount[i]);
                int256 creditChange = (paperChange *
                    orderList[i].creditAmount) / orderList[i].paperAmount;
                int256 fee = int256(creditChange.abs()).decimalMul(
                    _info2MakerFeeRate(orderList[i].info)
                );
                // serialNum is used for frontend level PNL calculation
                uint256 serialNum = state.positionSerialNum[
                    orderList[i].signer
                ][result.perp];
                emit OrderFilled(
                    orderHashList[i],
                    orderList[i].signer,
                    result.perp,
                    paperChange,
                    creditChange - fee,
                    serialNum
                );
                // store matching result, including fees
                result.paperChangeList[currentTraderIndex] += paperChange;
                result.creditChangeList[currentTraderIndex] += creditChange;
                result.creditChangeList[currentTraderIndex] -= fee;
                result.paperChangeList[0] -= paperChange;
                result.creditChangeList[0] -= creditChange;
                result.orderSenderFee += fee;

                unchecked {
                    ++i;
                }
            }
        }

        // trading fee related
        {
            // calculate takerFee based on taker's credit matching amount
            int256 takerFee = int256(result.creditChangeList[0].abs())
                .decimalMul(_info2TakerFeeRate(orderList[0].info));
            result.creditChangeList[0] -= takerFee;
            result.orderSenderFee += takerFee;
            emit OrderFilled(
                orderHashList[0],
                orderList[0].signer,
                result.perp,
                result.paperChangeList[0],
                result.creditChangeList[0],
                state.positionSerialNum[orderList[0].signer][result.perp]
            );
            // charge fee
            state.primaryCredit[orderSender] += result.orderSenderFee;
            // if orderSender pay traders, check if orderSender is safe
            if (result.orderSenderFee < 0) {
                require(
                    Liquidation._isSolidSafe(state, orderSender),
                    Errors.ORDER_SENDER_NOT_SAFE
                );
            }
        }

        // check if trader safe
        _checkIsTraderSafe(state, result);
    }

    function _checkIsTraderSafe(
        Types.State storage state,
        Types.MatchResult memory result
    ) private view {
        // cache mark price to save gas
        uint256 totalPerpNum = state.registeredPerp.length;
        address[] memory perpList = new address[](totalPerpNum);
        int256[] memory markPriceCache = new int256[](totalPerpNum);
        // check each trader's maintenance margin and net value
        for (uint256 i = 0; i < result.traderList.length; i++) {
            address trader = result.traderList[i];
            uint256 maintenanceMargin;
            int256 netValue = state.primaryCredit[trader] +
                int256(state.secondaryCredit[trader]) +
                result.creditChangeList[i];
            for (uint256 j = 0; j < state.openPositions[trader].length; j++) {
                address perp = state.openPositions[trader][j];
                Types.RiskParams memory params = state.perpRiskParams[perp];
                int256 markPrice;
                // check if mark price is cached
                for (uint256 k = 0; k < totalPerpNum; k++) {
                    if (perpList[k] == perp) {
                        markPrice = markPriceCache[k];
                        break;
                    }
                    // if not, query mark price and cache it
                    if (perpList[k] == address(0)) {
                        markPrice = int256(
                            IMarkPriceSource(params.markPriceSource)
                                .getMarkPrice()
                        );
                        perpList[k] = perp;
                        markPriceCache[k] = markPrice;
                        break;
                    }
                }
                (int256 paperAmount, int256 credit) = IPerpetual(perp)
                    .balanceOf(trader);
                // add the paper change right now
                if (perp == result.perp) {
                    paperAmount += result.paperChangeList[i];
                }
                maintenanceMargin += paperAmount.decimalMul(markPrice).abs() * params.liquidationThreshold / 10**18;
                netValue += paperAmount.decimalMul(markPrice) + credit;
            }
            require(
                netValue >= int256(maintenanceMargin),
                Errors.ACCOUNT_NOT_SAFE
            );
        }
    }

    // ========== position register ==========

    function _addPosition(
        Types.State storage state,
        address perp,
        address trader
    ) internal {
        Types.RiskParams memory params = state.perpRiskParams[msg.sender];
        require(params.isRegistered, Errors.PERP_NOT_REGISTERED);
        if (!state.hasPosition[trader][perp]) {
            state.hasPosition[trader][perp] = true;
            state.openPositions[trader].push(perp);
        }
    }

    function _realizePnl(Types.State storage state, address trader, int256 pnl)
        internal
    {
        Types.RiskParams memory params = state.perpRiskParams[msg.sender];
        require(params.isRegistered, Errors.PERP_NOT_REGISTERED);

        state.hasPosition[trader][msg.sender] = false;
        state.primaryCredit[trader] += pnl;
        state.positionSerialNum[trader][msg.sender] += 1;

        address[] storage positionList = state.openPositions[trader];
        for (uint256 i = 0; i < positionList.length; i++) {
            if (positionList[i] == msg.sender) {
                positionList[i] = positionList[positionList.length - 1];
                positionList.pop();
                break;
            }
        }
    }

    // ========== order check ==========

    function _priceMatchCheck(
        Types.Order memory takerOrder,
        Types.Order memory makerOrder
    ) private pure {
        /*
            Requirements:
            takercredit * abs(makerpaper) / abs(takerpaper) + makercredit <= 0
            makercredit - takercredit * makerpaper / takerpaper <= 0
            if takerPaper > 0
            makercredit * takerpaper <= takercredit * makerpaper
            if takerPaper < 0
            makercredit * takerpaper >= takercredit * makerpaper
        */

        // let temp1 = makercredit * takerpaper
        // let temp2 = takercredit * makerpaper
        int256 temp1 = int256(makerOrder.creditAmount) *
            int256(takerOrder.paperAmount);
        int256 temp2 = int256(takerOrder.creditAmount) *
            int256(makerOrder.paperAmount);

        if (takerOrder.paperAmount > 0) {
            // maker order should be in the opposite direction of taker order
            require(makerOrder.paperAmount < 0, Errors.ORDER_PRICE_NOT_MATCH);
            require(temp1 <= temp2, Errors.ORDER_PRICE_NOT_MATCH);
        } else {
            // maker order should be in the opposite direction of taker order
            require(makerOrder.paperAmount > 0, Errors.ORDER_PRICE_NOT_MATCH);
            require(temp1 >= temp2, Errors.ORDER_PRICE_NOT_MATCH);
        }
    }

    function _structHash(Types.Order memory order)
        private
        pure
        returns (bytes32 structHash)
    {
        /*
            To save gas, we use assembly to implement the function:

            keccak256(
                abi.encode(
                    Types.ORDER_TYPEHASH,
                    order.perp,
                    order.signer,
                    order.paperAmount,
                    order.creditAmount,
                    order.info
                )
            )

            Method:
            Insert ORDER_TYPEHASH before order's memory head to construct the
            required memory structure. Get the hash of this structure and then
            restore it as is.
        */

        bytes32 orderTypeHash = Types.ORDER_TYPEHASH;
        assembly {
            let start := sub(order, 32)
            let tmp := mload(start)
            // 192 = (1 + 5) * 32
            // [0...32)   bytes: EIP712_ORDER_TYPE
            // [32...192) bytes: order
            mstore(start, orderTypeHash)
            structHash := keccak256(start, 192)
            mstore(start, tmp)
        }
    }

    // ========== data convert ==========

    function _info2MakerFeeRate(bytes32 info) private pure returns (int256) {
        bytes8 value = bytes8(info >> 192);
        int64 makerFee;
        assembly {
            makerFee := value
        }
        return int256(makerFee);
    }

    function _info2TakerFeeRate(bytes32 info)
        private
        pure
        returns (int256 takerFeeRate)
    {
        bytes8 value = bytes8(info >> 128);
        int64 takerFee;
        assembly {
            takerFee := value
        }
        return int256(takerFee);
    }

    function _info2Expiration(bytes32 info) private pure returns (uint256) {
        bytes8 value = bytes8(info >> 64);
        uint64 expiration;
        assembly {
            expiration := value
        }
        return uint256(expiration);
    }
}
