/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../intf/IDealer.sol";
import "../intf/IPerpetual.sol";
import "../intf/IMarkPriceSource.sol";
import "../utils/SignedDecimalMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract DegenSubaccount {

    using SignedDecimalMath for int256;
    // ========== storage ==========

    address public owner;
    bool public initialized;
    address private JOJOOperator;
    address public dealer;


    // ========== modifier ==========

    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    modifier onlyGlobalOperator() {
        require(JOJOOperator == msg.sender, "Ownable: caller is not the globalOperator");
        _;
    }


    // ========== functions ==========

    function init(address _owner, address _dealer, address _operator) external {
        require(!initialized, "ALREADY INITIALIZED");
        initialized = true;
        owner = _owner;
        dealer = _dealer;
        JOJOOperator = _operator;
        IDealer(dealer).setOperator(JOJOOperator, true);
        IDealer(dealer).setOperator(owner, true);
    }



    /// @param isValid authorize operator if value is true
    /// unauthorize operator if value is false
    //can not delete operator
    function setOperator(address operator, bool isValid) external onlyOwner {
        if(operator == JOJOOperator){
            require(isValid == true, "can not update globalOperator to false");
        }
        IDealer(dealer).setOperator(operator, isValid);
    }

    function getMaxWithdrawAmount(address trader) public view returns(uint256, uint256) {

        (int256 primaryCredit,, uint256 pendingPrimaryWithdraw,,)= IDealer(dealer).getCreditOf(address(this));

        uint256 positionMargin;
        int256 positionNetValue;
        address[] memory positions = IDealer(dealer).getPositions(trader);

        for (uint256 i = 0; i < positions.length; ) {

            (int256 paperAmount, int256 creditAmount) = IPerpetual(positions[i]).balanceOf(trader);

            Types.RiskParams memory params = IDealer(dealer).getRiskParams(positions[i]);
            int256 price = SafeCast.toInt256(
                IMarkPriceSource(params.markPriceSource).getMarkPrice()
            );
            positionMargin += paperAmount.decimalMul(price).abs() * 1e16 / 1e18;

            positionNetValue += paperAmount.decimalMul(price) + creditAmount;
            unchecked {
                ++i;
            }
        }

        int256 netValue = positionNetValue + primaryCredit;
        require(netValue > 0, "netValue is less than 0");
        require(SafeCast.toUint256(netValue) >= positionMargin, "netValue is less than maintenance margin");
        uint256 maxWithxdrawAmount =  SafeCast.toUint256(netValue) - positionMargin;
        return (maxWithxdrawAmount, pendingPrimaryWithdraw);

    }

    // primary
    function requestWithdrawPrimaryAsset(uint256 withdrawAmount) external onlyOwner {
        (uint256 maxWithdrawValue,) = getMaxWithdrawAmount(address(this));
        require(withdrawAmount <= maxWithdrawValue, "withdraw amount is too big");
        IDealer(dealer).requestWithdraw(address(this), withdrawAmount, 0);
    }

    function executeWithdrawPrimaryAsset(address to, bool toInternal) external onlyOwner {
        (uint256 maxWithdrawValue, uint256 pendingPrimaryWithdraw) = getMaxWithdrawAmount(address(this));
        require(pendingPrimaryWithdraw <= maxWithdrawValue, "withdraw amount is too big");
        IDealer(dealer).executeWithdraw(address(this), to, toInternal, "");
    }


    // secondary
    function requestWithdrawSecondaryAsset(uint256 secondaryAmount) external onlyGlobalOperator {
        // only Global operator can request JUSD
        IDealer(dealer).requestWithdraw(address(this), 0, secondaryAmount);

    }

    function executeWithdrawSecondaryAsset() external onlyGlobalOperator {
        // only Global operator can withdraw JUSD
        IDealer(dealer).executeWithdraw(address(this), JOJOOperator, false, "");
    }
}
