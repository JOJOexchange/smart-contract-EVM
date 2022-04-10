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

    /*
        We use int128 to store paper and reduced credit.
        So we could store balance in a single slot.
        This can help us save gas.

        int128 can support size of 1.7E38, which is enough for most cases.
        But other than here, we use int256 to get higher accuracy of calculation.
        Devs should keep in mind that even int256 is allowed in some places, 
        you should not pass in a value exceed int128.
    */
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

    /*
        To update all credit after funding rate updated,
        we store "reducedCredit" instead of credit itself.
        
        credit = (paper * fundingRate) + reducedCredit

        FundingRate here is a little different from what it means at CEX.
        FundingRate is a cumulative value, its absolute size has no meaning, 
        only the absolute value that increases or decreases with each update 
        has meaning.

        e.g. If the fundingRate increases by 5 at a certain update, 
        then you will receive 5 credit for every paper you long.
        And conversely, you will be charged 5credit for every paper you short.
    */

    function creditOf(address trader) public view returns (int256 credit) {
        credit =
            int256(balanceMap[trader].paper).decimalMul(
                IDealer(owner()).getFundingRate(address(this))
            ) +
            int256(balanceMap[trader].reducedCredit);
    }

    /// @inheritdoc IPerpetual
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

    /// @inheritdoc IPerpetual
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

    /// @inheritdoc IPerpetual
    function liquidate(
        address liquidatedTrader,
        int256 requestPaper,
        int256 expectCredit
    ) external returns (int256 liqtorPaperChange, int256 liqtorCreditChange) {
        // lt => liquidated trader, who holds dangerous position
        // ld => liquidator, who takerover the dangerous position
        int256 liqedPaperChange;
        int256 liqedCreditChange;
        (
            liqtorPaperChange,
            liqtorCreditChange,
            liqedPaperChange,
            liqedCreditChange
        ) = IDealer(owner()).requestLiquidate(
            msg.sender,
            liquidatedTrader,
            requestPaper
        );

        // expect price = expectCredit/requestPaper * -1
        // price = liqtorCreditChange/liqtorPaperChange * -1
        if (liqtorPaperChange < 0) {
            // open short, price >= expect price
            // liqtorCreditChange/liqtorPaperChange * -1 >= expectCredit/requestPaper * -1
            // liqtorCreditChange/liqtorPaperChange <= expectCredit/requestPaper
            require(liqtorCreditChange * requestPaper <= expectCredit * liqtorPaperChange, "LIQUIDATION_PRICE_PROTECTION");
        } else {
            // open long, price <= expect price
            // liqtorCreditChange/liqtorPaperChange * -1 <= expectCredit/requestPaper * -1
            // liqtorCreditChange/liqtorPaperChange >= expectCredit/requestPaper
            require(liqtorCreditChange * requestPaper >= expectCredit * liqtorPaperChange, "LIQUIDATION_PRICE_PROTECTION");
        }

        int256 rate = IDealer(owner()).getFundingRate(address(this));
        _settle(liquidatedTrader, rate, liqedPaperChange, liqedCreditChange);
        _settle(msg.sender, rate, liqtorPaperChange, liqtorCreditChange);
        require(IDealer(owner()).isSafe(msg.sender), "LIQUIDATOR_NOT_SAFE");
    }

    // ========== owner only adjustment ==========

    /// @inheritdoc IPerpetual
    function changeCredit(address trader, int256 amount) external onlyOwner {
        balanceMap[trader].reducedCredit += int128(amount);
        emit BalanceChange(trader, 0, amount);
    }

    // ========== settlement ==========

    /*
        Remember the fomular?
        credit = (paper * fundingRate) + reducedCredit

        So we have...
        reducedCredit = credit - (paper * fundingRate)

        When changing balances, you need to calculate the credit first.
        And then calculated the reducedCredit that should be stored.
    */

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
