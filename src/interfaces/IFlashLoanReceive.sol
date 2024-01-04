/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.9;

interface IFlashloanReceive {
    /// @dev implement this interface to develop a flashloan-compatible flashLoanReceiver contract
    /// @param asset is the amount of asset you want to flashloan.
    /// @param amount is the amount of asset you want to flashloan.
    /// @param param is the customized params pass by users
    function JOJOFlashLoan(
        address asset,
        uint256 amount,
        address to,
        bytes calldata param
    ) external;
}
