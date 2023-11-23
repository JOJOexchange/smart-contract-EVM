/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../intf/IDealer.sol";
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


    // ========== event ==========
    event ExecuteTransaction(address indexed owner, address subaccount, address to, bytes data, uint256 value);
    event UpdateMaxMultiple(uint256 oldMaxMultiple, uint256 newMaxMultiple);

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

    // primary
    function requestWithdrawPrimaryAsset(uint256 primaryAmount) external onlyOwner {
        (,,, uint256 maintenanceMargin) = IDealer(dealer).getTraderRisk(address(this));
        (int256 primaryCredit,,,,) = IDealer(dealer).getCreditOf(address(this));

        require(primaryCredit > 0, "primaryCredit is less than 0");
        require(primaryAmount + maintenanceMargin <= SafeCast.toUint256(primaryCredit), "withdraw amount is too big");
        IDealer(dealer).requestWithdraw(address(this), primaryAmount, 0);
    }

    function executeWithdrawPrimaryAsset(address to, bool toInternal) external onlyOwner {
        (,,, uint256 maintenanceMargin) = IDealer(dealer).getTraderRisk(address(this));
        (int256 primaryCredit,,uint256 pendingPrimaryWithdraw,,) = IDealer(dealer).getCreditOf(address(this));

        require(primaryCredit > 0, "primaryCredit is less than 0");
        require(pendingPrimaryWithdraw + maintenanceMargin <= SafeCast.toUint256(primaryCredit), "withdraw amount is too big");
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
