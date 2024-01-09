/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../interfaces/IDealer.sol";
import "../libraries/SignedDecimalMath.sol";

contract BotSubaccount {
    using SignedDecimalMath for int256;

    // ========== storage ==========

    address public owner;
    address public dealer;
    address private jojoOperator;
    bool public initialized;

    // ========== modifier ==========

    modifier onlyGlobalOperatorAndOwner() {
        require(jojoOperator == msg.sender || owner == msg.sender, "Ownable: caller is not the globalOperator or owner");
        _;
    }

    // ========== functions ==========

    /// @param _operator who can operate the botSubaccount
    /// @notice if the botSuaccount is created by subaccount,
    /// then `_operator` is the owner of subaccount.
    /// can not delete operator
    function init(address _owner, address _operator, address _dealer, address _JOJOoperator) external {
        require(!initialized, "ALREADY INITIALIZED");
        initialized = true;
        owner = _owner;
        dealer = _dealer;
        jojoOperator = _JOJOoperator;
        IDealer(dealer).setOperator(jojoOperator, true);
        require(!Address.isContract(_operator), "operator must be eoa");
        IDealer(dealer).setOperator(_operator, true);
    }

    function requestWithdrawAsset(uint256 primaryAmount, uint256 secondaryAmount) external onlyGlobalOperatorAndOwner {
        IDealer(dealer).requestWithdraw(address(this), primaryAmount, secondaryAmount);
    }

    function executeWithdrawAsset(address to, bool toInternal) external onlyGlobalOperatorAndOwner {
        if (msg.sender == jojoOperator) {
            require(to == owner, "globalOperator only can transfer to owner");
        }
        IDealer(dealer).executeWithdraw(address(this), to, toInternal, "");
    }

    function fastWithdrawAsset(
        address to,
        uint256 primaryAmount,
        uint256 secondaryAmount,
        bool isInternal
    )
        external
        onlyGlobalOperatorAndOwner
    {
        if (msg.sender == jojoOperator) {
            require(to == owner, "globalOperator only can transfer to owner");
        }

        IDealer(dealer).fastWithdraw(address(this), to, primaryAmount, secondaryAmount, isInternal, "");
    }
}
