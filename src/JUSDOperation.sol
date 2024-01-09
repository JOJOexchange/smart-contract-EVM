/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "./libraries/Errors.sol";
import "./libraries/SignedDecimalMath.sol";
import "./JUSDBankStorage.sol";

/// @notice Owner-only functions
abstract contract JUSDOperation is JUSDBankStorage {
    using SignedDecimalMath for uint256;

    //Event

    event RemoveReserve(address indexed collateral);

    event UpdateBorrowFeeRate(uint256 newBorrowFeeRate);

    event ReRegisterReserve(address indexed collateral);

    event UpdateOracle(address collateral, address newOracle);

    event UpdateInsurance(address oldInsurance, address newInsurance);

    event UpdateJOJODealer(address oldJOJODealer, address newJOJODealer);

    event UpdateMaxReservesAmount(uint256 maxReservesAmount, uint256 newMaxReservesAmount);

    event UpdateMaxBorrowAmount(uint256 maxPerAccountBorrowAmount, uint256 maxTotalBorrowAmount);

    event SetOperator(address indexed client, address indexed operator, bool isOperator);

    event UpdateReserveRiskParam(
        address indexed collateral,
        uint256 liquidationMortgageRate,
        uint256 liquidationPriceOff,
        uint256 insuranceFeeRate
    );

    event UpdateReserveParam(
        address indexed collateral,
        uint256 initialMortgageRate,
        uint256 maxTotalDepositAmount,
        uint256 maxDepositAmountPerAccount,
        uint256 maxBorrowValue
    );

    /// @notice initial the param of each reserve
    function initReserve(
        address _collateral,
        uint256 _initialMortgageRate,
        uint256 _maxTotalDepositAmount,
        uint256 _maxDepositAmountPerAccount,
        uint256 _maxColBorrowPerAccount,
        uint256 _liquidationMortgageRate,
        uint256 _liquidationPriceOff,
        uint256 _insuranceFeeRate,
        address _oracle
    )
        external
        onlyOwner
    {
        require(
            Types.ONE - _liquidationMortgageRate
                > _liquidationPriceOff + (Types.ONE - _liquidationPriceOff).decimalMul(_insuranceFeeRate),
            Errors.RESERVE_PARAM_ERROR
        );
        reserveInfo[_collateral].initialMortgageRate = _initialMortgageRate;
        reserveInfo[_collateral].maxTotalDepositAmount = _maxTotalDepositAmount;
        reserveInfo[_collateral].maxDepositAmountPerAccount = _maxDepositAmountPerAccount;
        reserveInfo[_collateral].maxColBorrowPerAccount = _maxColBorrowPerAccount;
        reserveInfo[_collateral].liquidationMortgageRate = _liquidationMortgageRate;
        reserveInfo[_collateral].liquidationPriceOff = _liquidationPriceOff;
        reserveInfo[_collateral].insuranceFeeRate = _insuranceFeeRate;
        reserveInfo[_collateral].isDepositAllowed = true;
        reserveInfo[_collateral].isBorrowAllowed = true;
        reserveInfo[_collateral].oracle = _oracle;
        _addReserve(_collateral);
    }

    /// @notice update the max borrow amount of total and per account
    function updateMaxBorrowAmount(
        uint256 _maxBorrowAmountPerAccount,
        uint256 _maxTotalBorrowAmount
    )
        external
        onlyOwner
    {
        maxTotalBorrowAmount = _maxTotalBorrowAmount;
        maxPerAccountBorrowAmount = _maxBorrowAmountPerAccount;
        emit UpdateMaxBorrowAmount(maxPerAccountBorrowAmount, maxTotalBorrowAmount);
    }

    /// @notice update the insurance account
    function updateInsurance(address newInsurance) external onlyOwner {
        emit UpdateInsurance(insurance, newInsurance);
        insurance = newInsurance;
    }

    /// @notice update JOJODealer address
    function updateJOJODealer(address newJOJODealer) external onlyOwner {
        emit UpdateJOJODealer(JOJODealer, newJOJODealer);
        JOJODealer = newJOJODealer;
    }

    /// @notice open liquidatorWhitelist
    function liquidatorWhitelistOpen() external onlyOwner {
        isLiquidatorWhitelistOpen = true;
    }

    /// @notice close liquidatorWhitelist
    function liquidatorWhitelistClose() external onlyOwner {
        isLiquidatorWhitelistOpen = false;
    }

    /// @notice add liquidatorWhitelist
    function addLiquidator(address liquidator) external onlyOwner {
        isLiquidatorWhiteList[liquidator] = true;
    }

    /// @notice rempve liquidatorWhitelist
    function removeLiquidator(address liquidator) external onlyOwner {
        isLiquidatorWhiteList[liquidator] = false;
    }

    /// @notice update collateral oracle
    function updateOracle(address collateral, address newOracle) external onlyOwner {
        Types.ReserveInfo storage reserve = reserveInfo[collateral];
        reserve.oracle = newOracle;
        emit UpdateOracle(collateral, newOracle);
    }

    /// @notice update maxReservesNum
    function updateMaxReservesAmount(uint256 newMaxReservesAmount) external onlyOwner {
        emit UpdateMaxReservesAmount(maxReservesNum, newMaxReservesAmount);
        maxReservesNum = newMaxReservesAmount;
    }

    /// @notice update the borrow fee rate
    function updateBorrowFeeRate(uint256 _borrowFeeRate) external onlyOwner {
        accrueRate();
        borrowFeeRate = _borrowFeeRate;
        emit UpdateBorrowFeeRate(_borrowFeeRate);
    }

    /// @notice update the reserve risk params
    function updateRiskParam(
        address collateral,
        uint256 _liquidationMortgageRate,
        uint256 _liquidationPriceOff,
        uint256 _insuranceFeeRate
    )
        external
        onlyOwner
    {
        require(
            Types.ONE - _liquidationMortgageRate
                > _liquidationPriceOff + ((Types.ONE - _liquidationPriceOff) * _insuranceFeeRate) / Types.ONE,
            Errors.RESERVE_PARAM_ERROR
        );

        require(reserveInfo[collateral].initialMortgageRate < _liquidationMortgageRate, Errors.RESERVE_PARAM_WRONG);
        reserveInfo[collateral].liquidationMortgageRate = _liquidationMortgageRate;
        reserveInfo[collateral].liquidationPriceOff = _liquidationPriceOff;
        reserveInfo[collateral].insuranceFeeRate = _insuranceFeeRate;
        emit UpdateReserveRiskParam(collateral, _liquidationMortgageRate, _liquidationPriceOff, _insuranceFeeRate);
    }

    /// @notice update the reserve basic params
    function updateReserveParam(
        address collateral,
        uint256 _initialMortgageRate,
        uint256 _maxTotalDepositAmount,
        uint256 _maxDepositAmountPerAccount,
        uint256 _maxColBorrowPerAccount
    )
        external
        onlyOwner
    {
        require(_initialMortgageRate < reserveInfo[collateral].liquidationMortgageRate, Errors.RESERVE_PARAM_WRONG);
        reserveInfo[collateral].initialMortgageRate = _initialMortgageRate;
        reserveInfo[collateral].maxTotalDepositAmount = _maxTotalDepositAmount;
        reserveInfo[collateral].maxDepositAmountPerAccount = _maxDepositAmountPerAccount;
        reserveInfo[collateral].maxColBorrowPerAccount = _maxColBorrowPerAccount;
        emit UpdateReserveParam(
            collateral,
            _initialMortgageRate,
            _maxTotalDepositAmount,
            _maxDepositAmountPerAccount,
            _maxColBorrowPerAccount
        );
    }

    /// @notice remove the reserve, need to modify the market status
    function delistReserve(address collateral) external onlyOwner {
        Types.ReserveInfo storage reserve = reserveInfo[collateral];
        reserve.isBorrowAllowed = false;
        reserve.isDepositAllowed = false;
        reserve.isFinalLiquidation = true;
        emit RemoveReserve(collateral);
    }

    /// @notice relist the delist reserve
    function relistReserve(address collateral) external onlyOwner {
        Types.ReserveInfo storage reserve = reserveInfo[collateral];
        reserve.isBorrowAllowed = true;
        reserve.isDepositAllowed = true;
        reserve.isFinalLiquidation = false;
        emit ReRegisterReserve(collateral);
    }

    /// @notice Update the sub account
    function setOperator(address operator, bool isOperator) external {
        operatorRegistry[msg.sender][operator] = isOperator;
        emit SetOperator(msg.sender, operator, isOperator);
    }

    function _addReserve(address collateral) private {
        require(reservesNum < maxReservesNum, Errors.NO_MORE_RESERVE_ALLOWED);
        reservesList.push(collateral);
        reservesNum += 1;
    }
}
