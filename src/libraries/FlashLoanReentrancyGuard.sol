/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

abstract contract FlashLoanReentrancyGuard {
    uint256 private constant _CAN_FLASHLOAN = 1;
    uint256 private constant _CAN_NOT_FLASHLOAN = 2;

    uint256 private _status;

    constructor() {
        _status = _CAN_FLASHLOAN;
    }

    modifier nonFlashLoanReentrant() {
        require(
            _status != _CAN_NOT_FLASHLOAN, "ReentrancyGuard: Withdraw or Borrow or Liquidate flashLoan reentrant call"
        );

        _status = _CAN_NOT_FLASHLOAN;

        _;

        _status = _CAN_FLASHLOAN;
    }
}
