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

contract BotSubaccount {

    using SignedDecimalMath for int256;
    // ========== storage ==========

    address public owner;
    bool public initialized;
    address private JOJOOperator;
    address public dealer;


    // ========== modifier ==========

    modifier onlyGlobalOperatorAndOwner() {
        require(JOJOOperator == msg.sender || owner == msg.sender, "Ownable: caller is not the globalOperator or owner");
        _;
    }


    // ========== functions ==========

    function init( address _owner, address _operator, address _dealer, address _JOJOoperator) external {
        require(!initialized, "ALREADY INITIALIZED");
        initialized = true;
        owner = _owner;
        dealer = _dealer;
        JOJOOperator = _JOJOoperator;
        IDealer(dealer).setOperator(JOJOOperator, true);
        // _operator must be eoa
        require(!Address.isContract(_operator), "operator must be eoa");
        IDealer(dealer).setOperator(_operator, true);
    }


    function requestWithdrawAsset(uint256 primaryAmount, uint256 secondaryAmount) external onlyGlobalOperatorAndOwner {
        IDealer(dealer).requestWithdraw(address(this), primaryAmount, secondaryAmount);
    }

    function executeWithdrawAsset(address to, bool toInternal) external onlyGlobalOperatorAndOwner {
        if(msg.sender == JOJOOperator){
            require(to == owner, "globalOperator only can transfer to owner");
        }
        IDealer(dealer).executeWithdraw(address(this), to, toInternal, "");
    }

}
