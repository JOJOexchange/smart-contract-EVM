/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../intf/IPerpetual.sol";
import "../intf/IMarkPriceSource.sol";
import "./JOJOBase.sol";
import "../utils/SignedDecimalMath.sol";
import "../utils/Errors.sol";

contract JOJOFunding is JOJOBase {
    using SafeERC20 for IERC20;
    using SignedDecimalMath for int256;

    mapping(address => int256) public trueCredit; // created by deposit funding, can be converted to funding
    mapping(address => uint256) public virtualCredit; // for market maker, can not converted to any asset, only for trading

    mapping(address => address[]) public openPositions; // all user's open positions
    mapping(address => mapping(address => bool)) public hasPosition; // user => perp => hasPosition

    uint256 withdrawTimeLock;
    mapping(address => uint256) pendingWithdraw;
    mapping(address => uint256) requestWithdrawTimestamp;

    // Events
    event Deposit(address indexed to, address indexed payer, uint256 amount);

    event Withdraw(address indexed to, address indexed payer, uint256 amount);

    function setVirtualCredit(address trader, uint256 amount)
        external
        onlyOwner
    {
        virtualCredit[trader] = amount;
    }

    function deposit(uint256 amount, address to) external nonReentrant {
        IERC20(underlyingAsset).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        trueCredit[to] += int256(amount);
        emit Deposit(to, msg.sender, amount);
    }

    function withdraw(uint256 amount, address to) external nonReentrant {
        require(
            trueCredit[msg.sender] >= int256(amount),
            Errors.CREDIT_NOT_ENOUGH
        );
        if (withdrawTimeLock == 0) {
            _withdraw(msg.sender, to, amount);
        } else {
            pendingWithdraw[msg.sender] = amount;
            requestWithdrawTimestamp[msg.sender] = block.timestamp;
        }
    }

    function withdrawPendingFund(address to) external nonReentrant {
        require(requestWithdrawTimestamp[msg.sender]+withdrawTimeLock <= block.timestamp, "TN");
        uint256 amount = requestWithdrawTimestamp[msg.sender];
        _withdraw(msg.sender, to, amount);
        pendingWithdraw[msg.sender] = 0;
    } 

    function _withdraw(address payer, address to, uint256 amount) internal {
        trueCredit[payer] -= int256(amount);
            IERC20(underlyingAsset).safeTransfer(to, amount);
            require(isSafe(payer), Errors.ACCOUNT_NOT_SAFE);
            emit Withdraw(to, payer, amount);
    }

    function getTotalExposure(address trader)
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
        for (uint256 i = 0; i < openPositions[trader].length; i++) {
            (int256 paperAmount, int256 credit) = IPerpetual(
                openPositions[trader][i]
            ).balanceOf(trader);
            riskParams memory params = perpRiskParams[openPositions[trader][i]];
            (uint256 price, , ) = IMarkPriceSource(params.markPriceSource)
                .getMarkPrice();
            int256 signedExposure = paperAmount.decimalMul(int256(price));

            netValueDelta = signedExposure + credit;
            exposureDelta = signedExposure.abs();
            threshold = params.liquidationThreshold;

            // no position in this case
            if (exposureDelta == 0) {
                _removePosition(trader, i);
                // clear remaining credit if needed
                // if netValueDelta < 0, deposit credit to perp
                // if netValueDelta > 0, withdraw credit from perp
                if (netValueDelta != 0) {
                    IPerpetual(openPositions[trader][i]).changeCredit(
                        trader,
                        -1 * netValueDelta
                    );
                    trueCredit[trader] += netValueDelta;
                }
            }

            netValue += netValueDelta;
            exposure += exposureDelta;
            if (threshold > liquidationThreshold) {
                liquidationThreshold = threshold;
            }
        }
    }

    // will be liquidated when price drop %
    // unable to pay debt if riskRatio<0
    // safe only if riskRatio<liquidationThreshold
    function getRiskRatio(address trader)
        public
        returns (int256 riskRatio, uint256 liquidationThreshold)
    {
        int256 netValue;
        uint256 exposure;
        (netValue, exposure, liquidationThreshold) = getTotalExposure(trader);
        netValue =
            netValue +
            trueCredit[trader] +
            int256(virtualCredit[trader]);
        riskRatio = netValue.decimalDiv(int256(exposure));
    }

    function isSafe(address trader) public returns (bool) {
        if (openPositions[trader].length == 0) {
            return true;
        }
        (int256 riskRatio, uint256 liquidationThreshold) = getRiskRatio(trader);
        return riskRatio <= int256(liquidationThreshold);
    }

    // if the brokenTrader in long position, liquidatePaperAmount < 0 and liquidateCreditAmount > 0;
    function getLiquidateCreditAmount(
        address brokenTrader,
        int256 liquidatePaperAmount
    )
        external
        perpRegistered(msg.sender)
        returns (int256 paperAmount, int256 creditAmount)
    {
        require(!isSafe(brokenTrader), Errors.ACCOUNT_IS_SAFE);

        // get price
        riskParams memory params = perpRiskParams[msg.sender];
        (uint256 price, , ) = IMarkPriceSource(params.markPriceSource)
            .getMarkPrice();
        uint256 priceOffset = (price * params.liquidationPriceOff) / 10**18;

        // calculate trade
        (int256 brokenPaperAmount, ) = IPerpetual(msg.sender).balanceOf(
            brokenTrader
        );
        require(brokenPaperAmount != 0, Errors.TRADER_HAS_NO_POSITION);

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
        IPerpetual(msg.sender).changeCredit(insurance, int256(insuranceFee));
    }

    function handleBadDebt(address brokenTrader) external onlyOwner {
        require(!isSafe(brokenTrader), Errors.ACCOUNT_IS_SAFE);
        require(
            openPositions[brokenTrader].length == 0,
            Errors.TRADER_STILL_IN_LIQUIDATION
        );
        trueCredit[insurance] += trueCredit[brokenTrader];
        trueCredit[brokenTrader] = 0;
        virtualCredit[brokenTrader] = 0;
    }

    function _addPosition(address perp, address trader) internal {
        if (!hasPosition[trader][perp]) {
            hasPosition[trader][perp] = true;
            openPositions[trader].push(perp);
        }
    }

    function _removePosition(address trader, uint256 index) internal {
        address[] storage positionList = openPositions[trader];
        hasPosition[trader][positionList[index]] = false;
        positionList[index] = positionList[positionList.length - 1];
        positionList.pop();
    }
}
