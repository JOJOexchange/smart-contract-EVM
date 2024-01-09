/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

/// @notice Decimal math for int256. Round down.
library SignedDecimalMath {
    int256 constant SignedONE = 10 ** 18;
    uint256 constant ONE = 1e18;

    function decimalMul(int256 a, int256 b) internal pure returns (int256) {
        return (a * b) / SignedONE;
    }

    function decimalDiv(int256 a, int256 b) internal pure returns (int256) {
        return (a * SignedONE) / b;
    }

    function abs(int256 a) internal pure returns (uint256) {
        return a < 0 ? uint256(a * -1) : uint256(a);
    }

    function decimalMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b) / ONE;
    }

    function decimalDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * ONE) / b;
    }

    function decimalRemainder(uint256 a, uint256 b) internal pure returns (bool) {
        if ((a * ONE) % b == 0) {
            return true;
        } else {
            return false;
        }
    }
}
