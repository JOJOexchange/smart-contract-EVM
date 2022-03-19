/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../intf/IDealer.sol";
import "../intf/IPerpetual.sol";
import "../utils/SignedDecimalMath.sol";

contract Perpetual is Ownable, IPerpetual {
    using SignedDecimalMath for int256;

    // storage
    mapping(address => int256) public paperAmountMap;
    mapping(address => int256) public reducedCreditMap;

    // modifier

    // constructor
    constructor(address _owner) Ownable() {
        transferOwnership(_owner);
    }

    // function
    function creditOf(address trader) public view returns (int256 credit) {
        credit =
            paperAmountMap[trader].decimalMul(
                IDealer(owner()).getFundingRatio(address(this))
            ) +
            reducedCreditMap[trader];
    }

    function balanceOf(address trader)
        public
        view
        returns (int256 paperAmount, int256 credit)
    {
        paperAmount = paperAmountMap[trader];
        credit = creditOf(trader);
    }

    function trade(bytes calldata tradeData) external {
        (
            address taker,
            address[] memory makerList,
            int256[] memory tradePaperAmountList,
            int256[] memory tradeCreditAmountList
        ) = IDealer(owner()).approveTrade(msg.sender, tradeData);

        for (uint256 i = 0; i < makerList.length; i++) {
            _trade(
                taker,
                makerList[i],
                tradePaperAmountList[i],
                tradeCreditAmountList[i]
            );
        }

        for (uint256 i = 0; i < makerList.length; i++) {
            require(IDealer(owner()).isSafe(makerList[i]), "MAKER BROKEN");
        }
        require(IDealer(owner()).isSafe(taker), "TAKER BROKEN");
    }

    // when you liquidate a long position, liqudatePaperAmount < 0 and liquidateCreditAmount > 0
    function liquidate(address brokenTrader, int256 liquidatePaperAmount)
        external
    {
        (int256 paperAmount, int256 creditAmount) = IDealer(owner())
            .getLiquidateCreditAmount(brokenTrader, liquidatePaperAmount);

        _trade(msg.sender, brokenTrader, paperAmount, creditAmount);
        IDealer(owner()).isSafe(msg.sender);
    }

    function _trade(
        address taker,
        address maker,
        int256 tradePaperAmount,
        int256 tradeCreditAmount
    ) internal {
        require(
            (tradePaperAmount > 0 && tradeCreditAmount <= 0) ||
                (tradePaperAmount <= 0 && tradeCreditAmount > 0)
        );

        int256 ratio = IDealer(owner()).getFundingRatio(address(this));

        // ratio = 1000000000000000000
        // tradePaper = 1000000000000000000
        // tradeCredit = -30000000000000000000000
        // takerCredit = -30000000000000000000000
        // paperAmountMap[taker] = 1000000000000000000
        // reduced =

        // settle taker
        int256 takerCredit = paperAmountMap[taker].decimalMul(ratio) +
            reducedCreditMap[taker] +
            tradeCreditAmount;
        paperAmountMap[taker] += tradePaperAmount;
        reducedCreditMap[taker] =
            takerCredit -
            paperAmountMap[taker].decimalMul(ratio);

        // settle maker
        // -1 * tradePaperAmount & -1 * tradeCreditAmount
        int256 makerCredit = paperAmountMap[maker].decimalMul(ratio) +
            reducedCreditMap[maker] +
            (-1 * tradeCreditAmount);
        paperAmountMap[maker] += (-1 * tradePaperAmount);
        reducedCreditMap[maker] =
            makerCredit -
            paperAmountMap[maker].decimalMul(ratio);
    }

    function changeCredit(address trader, int256 amount) external onlyOwner {
        reducedCreditMap[trader] += amount;
    }
}

// credit = （paper * ratio）+ reducedCredit
// reducedCredit = credit - (paper * ratio)

// paper = 10
// ratio = -2
// reducedCredit = -1000

// credit = -1020

// =》

// open 1 long with price 200
// paper -> 11
// ratio = -2
// reducedCredit = -1198

// credit -> -1220

// swapPaperAmount
// swapCreditAmount
// counterparty
// if counterparty is contract => allowPerpetualSwap(counterparty, swapPaperAmount, swapCreditAmount) reutrns (bool)
// if counterparty is EOA => signature

// TODO check 0 dividen
