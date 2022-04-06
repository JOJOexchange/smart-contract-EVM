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

    // ========== storage ==========

    struct balance {
        int128 paper;
        int128 reducedCredit;
    }
    mapping(address => balance) public balanceMap;

    // ========== events ==========

    event BalanceChange(
        address indexed trader,
        int256 paperChange,
        int256 creditChange
    );

    // ========== constructor ==========

    constructor(address _owner) Ownable() {
        transferOwnership(_owner);
    }

    // ========== balance related ==========

    function creditOf(address trader) public view returns (int256 credit) {
        credit =
            int256(balanceMap[trader].paper).decimalMul(
                IDealer(owner()).getFundingRate(address(this))
            ) +
            int256(balanceMap[trader].reducedCredit);
    }

    function balanceOf(address trader)
        public
        view
        returns (int256 paper, int256 credit)
    {
        paper = int256(balanceMap[trader].paper);
        credit =
            paper.decimalMul(IDealer(owner()).getFundingRate(address(this))) +
            int256(balanceMap[trader].reducedCredit);
    }

    // ========== trade ==========

    function trade(bytes calldata tradeData) external {
        (
            address[] memory traderList,
            int256[] memory paperChangeList,
            int256[] memory creditChangeList
        ) = IDealer(owner()).approveTrade(msg.sender, tradeData);

        int256 rate = IDealer(owner()).getFundingRate(address(this));

        for (uint256 i = 0; i < traderList.length; i++) {
            address trader = traderList[i];
            _settle(trader, rate, paperChangeList[i], creditChangeList[i]);
            require(IDealer(owner()).isSafe(trader), "TRADER_NOT_SAFE");
        }
    }

    // ========== liquidation ==========

    function liquidate(address liquidatedTrader, uint256 requestPaperAmount)
        external
    {
        (
            int256 liquidatorPaperChange,
            int256 liquidatorCreditChange,
            int256 ltPaperChange,
            int256 ltCreditChange
        ) = IDealer(owner()).requestLiquidate(
                msg.sender,
                liquidatedTrader,
                requestPaperAmount
            );
        int256 rate = IDealer(owner()).getFundingRate(address(this));
        _settle(liquidatedTrader, rate, ltPaperChange, ltCreditChange);
        _settle(
            msg.sender,
            rate,
            liquidatorPaperChange,
            liquidatorCreditChange
        );
        require(IDealer(owner()).isSafe(msg.sender), "LIQUIDATOR_NOT_SAFE");
    }

    // ========== owner only adjustment ==========

    function changeCredit(address trader, int256 amount) external onlyOwner {
        balanceMap[trader].reducedCredit += int128(amount);
    }

    // ========== settlement ==========

    function _settle(
        address trader,
        int256 rate,
        int256 paperChange,
        int256 creditChange
    ) internal {
        int256 credit = int256(balanceMap[trader].paper).decimalMul(rate) +
            int256(balanceMap[trader].reducedCredit) +
            creditChange;
        int128 newPaper = balanceMap[trader].paper + int128(paperChange);
        int128 newReducedCredkt = int128(
            credit - int256(newPaper).decimalMul(rate)
        );
        balanceMap[trader].paper = newPaper;
        balanceMap[trader].reducedCredit = newReducedCredkt;
        emit BalanceChange(trader, paperChange, creditChange);
        if (balanceMap[trader].paper == 0) {
            IDealer(owner()).positionClear(trader);
        }
    }
}

// credit = （paper * rate）+ reducedCredit
// reducedCredit = credit - (paper * rate)

// paper = 10
// rate = -2
// reducedCredit = -1000

// credit = -1020

// =》

// open 1 long with price 200
// paper -> 11
// rate = -2
// reducedCredit = -1198

// credit -> -1220

// swapPaperAmount
// swapCreditAmount
// counterparty
// if counterparty is contract => allowPerpetualSwap(counterparty, swapPaperAmount, swapCreditAmount) reutrns (bool)
// if counterparty is EOA => signature
