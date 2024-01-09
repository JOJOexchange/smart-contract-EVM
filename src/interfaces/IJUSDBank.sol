/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../libraries/Types.sol";

/// @notice JUSDBank is a mortgage lending system that supports ERC20 as collateral and issues JUSD
/// JUSD is a self-issued stable coin used to support multi-collateralization protocols
interface IJUSDBank {
    /// @notice deposit function: user deposit their collateral.
    /// @param from: deposit from which account
    /// @param collateral: deposit collateral type.
    /// @param amount: collateral amount
    /// @param to: account that user want to deposit to
    function deposit(address from, address collateral, uint256 amount, address to) external;

    /// @notice borrow function: get JUSD based on the amount of user's collaterals.
    /// @param amount: borrow JUSD amount
    /// @param to: is the address receiving JUSD
    /// @param isDepositToJOJO: whether deposit to JOJO account
    function borrow(uint256 amount, address to, bool isDepositToJOJO) external;

    /// @notice withdraw function: user can withdraw their collateral
    /// @param collateral: withdraw collateral type
    /// @param amount: withdraw amount
    /// @param to: is the address receiving asset
    /// @param isInternal: if deposit to jojo or withdraw to wallet
    function withdraw(address collateral, uint256 amount, address to, bool isInternal) external;

    /// @notice repay function: repay the JUSD in order to avoid account liquidation by liquidators
    /// @param amount: repay JUSD amount
    /// @param to: repay to whom
    function repay(uint256 amount, address to) external returns (uint256);

    /// @notice If the value of the mortgage collaterals cannot cover the value of JUSD borrowed,
    /// the collaterals may be liquidated.
    /// Liquidation is divided into three steps:
    /// 1. determine whether liquidatedTrader is safe
    /// 2. calculate the collateral amount actually liquidated
    /// 3. transfer the insurance fee
    /// @param liquidatedTrader: is the trader to be liquidated
    /// @param liquidationCollateral: is the liquidated collateral type
    /// @param liquidator: is who liquidate others
    /// @param liquidationAmount: is the collateral amount liqidator want to take
    /// @param param: is the customized param passed by users. During the code of liquidation, system will
    /// call flashloan function so that users can pass any param they want to do more operations.
    /// @param expectPrice: expect liquidate amount
    function liquidate(
        address liquidatedTrader,
        address liquidationCollateral,
        address liquidator,
        uint256 liquidationAmount,
        bytes memory param,
        uint256 expectPrice
    )
        external
        returns (Types.LiquidateData memory liquidateData);

    /// @notice insurance account take bad debts on unsecured accounts
    /// @param liquidatedTraders traders who have bad debts
    function handleDebt(address[] calldata liquidatedTraders) external;

    /// @notice withdraw and deposit collaterals in one transaction
    /// @param receiver address who receiver the collateral
    /// @param collateral collateral type
    /// @param amount withdraw amount
    /// @param to: if repay JUSD, repay to whom
    /// @param param users input
    function flashLoan(address receiver, address collateral, uint256 amount, address to, bytes memory param) external;

    /// @notice get the all collateral list
    function getReservesList() external view returns (address[] memory);

    /// @notice return the max borrow JUSD amount from the deposit amount
    function getDepositMaxMintAmount(address user) external view returns (uint256);

    /// @notice return the collateral's max borrow JUSD amount
    function getCollateralMaxMintAmount(
        address collateral,
        uint256 amoount
    )
        external
        view
        returns (uint256 maxAmount);

    /// @notice return the collateral's max withdraw amount
    function getMaxWithdrawAmount(address collateral, address user) external view returns (uint256 maxAmount);

    /// @notice return is account safe
    function isAccountSafe(address user) external view returns (bool);

    /// @notice get collateral price
    function getCollateralPrice(address collateral) external view returns (uint256);

    /// @notice get if has collateral
    function getIfHasCollateral(address from, address collateral) external view returns (bool);

    /// @notice get deposit balance
    function getDepositBalance(address collateral, address from) external view returns (uint256);

    /// @notice get borrow balance
    function getBorrowBalance(address from) external view returns (uint256);

    /// @notice get user collateral list
    function getUserCollateralList(address from) external view returns (address[] memory);
}
