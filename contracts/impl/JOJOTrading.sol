pragma solidity 0.8.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "./JOJOBase.sol";
import "./JOJOFunding.sol";
import "../intf/IDealer.sol";
import "../intf/IPerpetual.sol";
import "../intf/IMarkPriceSource.sol";
import "../intf/ITradingProxy.sol";
import "../utils/SignedDecimalMath.sol";

contract JOJOTrading is JOJOFunding, EIP712("JOJO Order", "1") {
    using SignedMath for int256;
    using Math for uint256;

    mapping(bytes32 => uint256) public filledPaperAmount;

    // if you want to open long positon, set paperAmount > 0 and creditAmount < 0
    // if the sender want to charge fee, set feeRate < 0; if the sender want to rebate, set feeRate > 0;
    struct Order {
        address perp;
        int256 paperAmount;
        int256 creditAmount;
        int128 makerFeeRate;
        int128 takerFeeRate;
        address signer;
        address sender;
        uint256 expiration;
        uint256 salt;
    }

    bytes32 public constant ORDER_TYPEHASH =
        keccak256(
            "Order(address perp, int256 paperAmount, int256 creditAmount, int128 makerFeeRate, int128 takerFeeRate, address signer, address sender, uint256 expiration, uint256 salt)"
        );

    // charge fee from all makers and taker, then transfer the fee to sender
    // if the taker open long and maker open short, tradePaperAmount > 0
    // Pay attention to sorting when submitting, then de-duplicate here to save gas
    function approveTrade(address sender, bytes calldata tradeData)
        external
        nonReentrant
        perpRegistered(msg.sender)
        returns (
            address taker,
            address[] memory makerList,
            int256[] memory tradePaperAmountList,
            int256[] memory tradeCreditAmountList
        )
    {
        (
            Order memory takerOrder,
            bytes memory takerSignature,
            Order[] memory makerOrderList,
            bytes[] memory makerSignatureList,
            uint256[] memory matchPaperAmount
        ) = abi.decode(tradeData, (Order, bytes, Order[], bytes[], uint256[]));

        bytes32 takerOrderHash = _checkOrder(takerOrder, takerSignature);
        require(
            takerOrder.sender == sender || takerOrder.sender == address(0),
            "INVALID SENDER"
        );
        require(takerOrder.perp == msg.sender, "INVALID PERP");

        bytes32[] memory makerOrderHashList = new bytes32[](
            makerOrderList.length
        );
        for (uint256 i = 0; i < makerOrderList.length; i++) {
            makerOrderHashList[i] = _checkOrder(
                makerOrderList[i],
                makerSignatureList[i]
            );
            require(
                makerOrderList[i].sender == sender ||
                    makerOrderList[i].sender == address(0),
                "INVALID SENDER"
            );
        }

        // de-duplicate maker to save gas
        uint256 uniqueMakerNum = 1;
        for (uint256 i = 1; i < makerOrderList.length; i++) {
            if (makerOrderList[i].signer != makerOrderList[i - 1].signer) {
                uniqueMakerNum += 1;
            }
        }

        makerList = new address[](uniqueMakerNum);
        tradePaperAmountList = new int256[](uniqueMakerNum);
        tradeCreditAmountList = new int256[](uniqueMakerNum);
        int256[] memory makerFeeList = new int256[](uniqueMakerNum);

        uint256 totalFilledPaper;
        uint256 currentMakerIndex;

        for (uint256 i = 0; i < makerOrderList.length; i++) {
            Order memory makerOrder = makerOrderList[i];
            bytes32 makerOrderHash = makerOrderHashList[i];
            require(
                filledPaperAmount[makerOrderHash] + matchPaperAmount[i] <=
                    makerOrder.paperAmount.abs(),
                "FILLED EXCEED"
            );
            require(matchPaperAmount[i] > 0, "CAN NOT FILL ZERO");
            _matchCheck(takerOrder, makerOrder);
            int256 paper = takerOrder.paperAmount > 0
                ? int256(matchPaperAmount[i])
                : -1 * int256(matchPaperAmount[i]);

            // welcome new maker
            if (i > 0) {
                if (makerOrder.signer != makerOrderList[i - 1].signer) {
                    currentMakerIndex += 1;
                    addPosition(msg.sender, makerOrder.signer);
                }
            }

            tradePaperAmountList[currentMakerIndex] += paper;
            tradeCreditAmountList[currentMakerIndex] +=
                (paper * makerOrder.creditAmount) /
                makerOrder.paperAmount;
            makerFeeList[currentMakerIndex] +=
                int256(matchPaperAmount[i]) *
                makerOrder.makerFeeRate;

            totalFilledPaper += matchPaperAmount[i];
            filledPaperAmount[makerOrderHash] += matchPaperAmount[i];
        }
        require(
            filledPaperAmount[takerOrderHash] + totalFilledPaper <=
                takerOrder.paperAmount.abs()
        );
        filledPaperAmount[takerOrderHash] += totalFilledPaper;
        addPosition(msg.sender, taker);

        // trading fee related
        int256 senderFee;
        int256 takerFee = int256(totalFilledPaper) *
            int256(takerOrder.takerFeeRate);
        if (takerFee != 0) {
            IPerpetual(msg.sender).changeCredit(taker, takerFee);
            senderFee -= takerFee;
        }

        for (uint256 i = 0; i < makerList.length; i++) {
            if (makerFeeList[i] != 0) {
                IPerpetual(msg.sender).changeCredit(
                    makerList[i],
                    makerFeeList[i]
                );
                senderFee -= makerFeeList[i];
            }
        }

        if (senderFee != 0) {
            IPerpetual(msg.sender).changeCredit(sender, senderFee);
            if (senderFee < 0) {
                isSafe(sender);
            }
        }
    }

    function _matchCheck(Order memory takerOrder, Order memory makerOrder)
        private
        pure
    {
        require(takerOrder.perp == makerOrder.perp, "PERP NOT MATCH");
        // require
        // takercredit * abs(makerpaper) / abs(takerpaper) + makercredit <= 0
        // makercredit - takercredit * makerpaper / takerpaper <= 0
        // if takerPaper > 0
        // makercredit * takerpaper <= takercredit * makerpaper
        // if takerPaper < 0
        // makercredit * takerpaper >= takercredit * makerpaper
        if (takerOrder.paperAmount > 0) {
            // taker open long, tradePaperAmount > 0
            require(makerOrder.paperAmount < 0, "ORDER MATCH SIDE WRONG");
            require(
                makerOrder.creditAmount * takerOrder.paperAmount <=
                    takerOrder.creditAmount * makerOrder.paperAmount,
                "PRICE NOT MATCH"
            );
        } else {
            // taker open short, tradePaperAmount < 0
            require(makerOrder.paperAmount > 0, "ORDER MATCH SIDE WRONG");
            require(
                makerOrder.creditAmount * takerOrder.paperAmount >=
                    takerOrder.creditAmount * makerOrder.paperAmount,
                "PRICE NOT MATCH"
            );
        }
    }

    function _checkOrder(Order memory order, bytes memory signature)
        private
        returns (bytes32 orderHash)
    {
        orderHash = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ORDER_TYPEHASH,
                    order.perp,
                    order.paperAmount,
                    order.creditAmount,
                    order.signer,
                    order.sender,
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
                "INVALID SIGNATURE"
            );
        } else {
            require(
                ECDSA.recover(orderHash, signature) == order.signer,
                "INVALID SIGNATURE"
            );
        }
        require(order.paperAmount < 0 || order.creditAmount < 0);
    }
}
