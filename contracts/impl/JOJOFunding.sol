pragma solidity 0.8.12;
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
    }

    function withdraw(uint256 amount, address to) external nonReentrant {
        require(
            trueCredit[msg.sender] >= int256(amount),
            Errors.CREDIT_NOT_ENOUGH
        );
        trueCredit[msg.sender] -= int256(amount);
        IERC20(underlyingAsset).safeTransfer(to, amount);
        require(isSafe(msg.sender), Errors.ACCOUNT_NOT_SAFE);
        // todo timelock
    }

    function getSingleExposure(address perp, address trader)
        public
        perpRegistered(perp)
        returns (
            int256 netValue,
            uint256 exposure,
            uint256 liquidationThreshold
        )
    {
        (int256 paperAmount, int256 credit) = IPerpetual(perp).balanceOf(
            trader
        );
        riskParams memory params = perpRiskParams[perp];
        liquidationThreshold = params.liquidationThreshold;
        (uint256 price, , ) = IMarkPriceSource(params.markPriceSource)
            .getMarkPrice();
        int256 signedExposure = paperAmount.decimalMul(int256(price));
        netValue = signedExposure + credit;
        exposure = signedExposure.abs();
    }

    function getTotalExposure(address trader)
        public
        returns (
            int256 netValue,
            uint256 exposure,
            uint256 liquidationThreshold
        )
    {
        int256 netValueDelta = 0;
        uint256 exposureDelta = 0;
        uint256 threshold;
        for (uint256 i = 0; i < openPositions[trader].length; i++) {
            (netValueDelta, exposureDelta, threshold) = getSingleExposure(
                openPositions[trader][i],
                trader
            );
            if (exposureDelta == 0) {
                // no position in this case
                removePosition(trader, i);
                // clear remaining credit if needed
                if (netValueDelta != 0) {
                    accuCredit(
                        openPositions[trader][i],
                        trader,
                        -1 * netValueDelta
                    );
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

    function addPosition(address perp, address trader) internal {
        if (!hasPosition[trader][perp]) {
            hasPosition[trader][perp] = true;
            openPositions[trader].push(perp);
        }
    }

    function removePosition(address trader, uint256 index) internal {
        address[] storage positionList = openPositions[trader];
        hasPosition[trader][positionList[index]] = false;
        positionList[index] = positionList[positionList.length - 1];
        positionList.pop();
    }

    // if amount > 0, deposit credit to perp
    // if amount < 0, withdraw credit from perp
    function accuCredit(
        address perp,
        address trader,
        int256 amount
    ) internal {
        IPerpetual(perp).changeCredit(trader, amount);
        trueCredit[trader] -= amount;
    }
}
